import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';

import '../models/enums.dart';
import '../models/errors.dart';
import '../protocol/frames.dart' show FrameCodec;
import '../protocol/pairing_guard.dart';
import '../protocol/pairing_payload.dart';
import '../services/peer_registry.dart';
import '../sync/remote_validation.dart' show isUuid;
import '../util/hashing.dart';
import '../util/ids.dart';
import '../util/logger.dart';
import '../models/peer.dart';

/// An open desktop pairing window. Never persisted: closing the app or letting
/// the five minutes elapse invalidates it.
class PairingSession {
  const PairingSession({
    required this.payload,
    required this.manualCode,
    required this.startedAt,
    required this.expiresAt,
    required this.tokenBytes,
  });

  final PairingPayload payload;

  /// 8 groups of 4 base32 characters for manual entry (`PAIR-008`).
  final String manualCode;
  final DateTime startedAt;
  final DateTime expiresAt;
  final List<int> tokenBytes;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);
}

class PairingRequestRecord {
  const PairingRequestRecord({
    required this.requestId,
    required this.pollSecret,
    required this.clientInstanceId,
    required this.displayName,
    required this.platform,
    required this.protocolVersion,
    required this.confirmationCode,
    required this.requestedAt,
    required this.state,
    this.collected = false,
    this.issuedToken,
  });

  final String requestId;
  final String pollSecret;
  final String clientInstanceId;
  final String displayName;
  final String platform;
  final int protocolVersion;
  final String confirmationCode;
  final DateTime requestedAt;
  final PairingState state;

  /// True once the one-time token was handed to the phone.
  final bool collected;

  /// Only available while [state] == approved and [collected] == false.
  final String? issuedToken;

  PairingRequestRecord copyWith({
    PairingState? state,
    bool? collected,
    String? issuedToken,
    bool clearIssuedToken = false,
  }) =>
      PairingRequestRecord(
        requestId: requestId,
        pollSecret: pollSecret,
        clientInstanceId: clientInstanceId,
        displayName: displayName,
        platform: platform,
        protocolVersion: protocolVersion,
        confirmationCode: confirmationCode,
        requestedAt: requestedAt,
        state: state ?? this.state,
        collected: collected ?? this.collected,
        issuedToken:
            clearIssuedToken ? null : (issuedToken ?? this.issuedToken),
      );

  PairingRequestInfo get info => PairingRequestInfo(
        requestId: requestId,
        displayName: displayName,
        platform: platform,
        protocolVersion: protocolVersion,
        confirmationCode: confirmationCode,
        requestedAt: requestedAt,
        state: state,
      );
}

/// Desktop-side pairing manager (`docs/05` §Pairing, `PAIR-001`..`PAIR-005`).
///
/// The service owns the ephemeral session, rate limiting and approval state.
/// HTTP transport lives in `HostServer`; the UI listens to [requests] and
/// calls [approve] / [reject]. Secrets never leave this object except through
/// the one-time status response.
class PairingService {
  PairingService({
    required PeerRegistry peers,
    required Logger logger,
    required String hostDeviceId,
    required String hostName,
    required String fingerprint,
    required List<String> Function() hostsProvider,
    required int Function() portProvider,
    DateTime Function()? now,
  })  : _peers = peers,
        _logger = logger,
        _hostDeviceId = hostDeviceId,
        _hostName = hostName,
        _fingerprint = fingerprint,
        _hostsProvider = hostsProvider,
        _portProvider = portProvider,
        _now = now ?? DateTime.now;

  final PeerRegistry _peers;
  final Logger _logger;
  final String _hostDeviceId;
  final String _hostName;
  final String _fingerprint;
  final List<String> Function() _hostsProvider;
  final int Function() _portProvider;
  final DateTime Function() _now;

  final PairingRateLimiter _rateLimiter = PairingRateLimiter();

  PairingSession? _session;
  final Map<String, PairingRequestRecord> _requests =
      <String, PairingRequestRecord>{};
  final StreamController<PairingRequestInfo> _requestEvents =
      StreamController<PairingRequestInfo>.broadcast();
  final StreamController<PairingSession?> _sessionEvents =
      StreamController<PairingSession?>.broadcast();

  /// Approval cards to render. Emits on request, approval and rejection.
  Stream<PairingRequestInfo> get requests => _requestEvents.stream;

  /// The open session (or null after it is used/expired).
  Stream<PairingSession?> get sessions => _sessionEvents.stream;

  PairingSession? get currentSession {
    final s = _session;
    if (s == null) return null;
    if (s.isExpiredAt(_now())) {
      _session = null;
      return null;
    }
    return s;
  }

  List<PairingRequestInfo> get pendingRequests => [
        for (final r in _requests.values)
          if (r.state == PairingState.pendingApproval) r.info,
      ];

  bool get isOpen => currentSession != null;

  /// Start a 5-minute session. [manual] creates a 20-byte token so it fits the
  /// documented 8×4 base32 manual code; QR sessions use a full 256-bit token.
  PairingSession startSession({bool manual = false, Duration? ttl}) {
    final bytes =
        secureRandomBytes(manual ? 20 : PairingPayload.pairingTokenLength);
    final token = base64UrlToken(bytes);
    final now = _now();
    final expires = now.add(ttl ?? const Duration(minutes: 5));
    final payload = PairingPayload(
      hosts: _hostsProvider(),
      port: _portProvider(),
      fingerprint: _fingerprint,
      pairingToken: token,
      expiresAt: expires,
      deviceName: _hostName,
      deviceId: _hostDeviceId,
    );
    final session = PairingSession(
      payload: payload,
      manualCode: ManualPairingCode.encode(bytes),
      startedAt: now,
      expiresAt: expires,
      tokenBytes: bytes,
    );
    _session = session;
    _requests.clear();
    _rateLimiter.reset();
    _sessionEvents.add(session);
    _logger.info('pairing: session started', fields: {
      'manual': manual,
      'expires': expires.toUtc().toIso8601String(),
    });
    return session;
  }

  /// Close the session without approving anything.
  void cancelSession() {
    if (_session == null) return;
    _session = null;
    _sessionEvents.add(null);
  }

  /// Check the manual code typed on the phone (`PAIR-008`). Constant-time.
  bool verifyManualCode(String input) {
    final session = currentSession;
    if (session == null) return false;
    final entered = ManualPairingCode.decode(input);
    if (entered == null) return false;
    return ManualPairingCode.matches(entered, session.tokenBytes);
  }

  /// Handle `POST /v1/pair/request` (`docs/05`).
  Future<PairRequestResponse> handleRequest(PairRequest request) async {
    _rateLimiter.check();
    final session = currentSession;
    if (session == null) {
      throw const PairingFailedError(expired: true);
    }
    if (request.protocolVersion > FrameCodec.protocolVersion) {
      throw const UnsupportedVersionError(
          'this phone uses a newer protocol; update TwinDrop');
    }

    List<int>? tokenBytes;
    try {
      tokenBytes = _decodePairingToken(request.pairingToken);
    } on FormatException {
      tokenBytes = null;
    }
    final tokenOk = tokenBytes != null &&
        DeviceTokens.constantTimeEquals(
          base64UrlToken(tokenBytes),
          base64UrlToken(session.tokenBytes),
        );
    if (!tokenOk) {
      _rateLimiter.recordFailure();
      _logger.warn('pairing: bad token');
      throw const PairingFailedError();
    }
    if (!isUuid(request.clientInstanceId)) {
      _rateLimiter.recordFailure();
      throw const PairingFailedError();
    }
    _rateLimiter.recordSuccess();

    final existing = _requests.values
        .where((r) => r.clientInstanceId == request.clientInstanceId)
        .where((r) => r.state != PairingState.expired)
        .firstOrNull;
    if (existing != null) {
      return PairRequestResponse(
        requestId: existing.requestId,
        pollSecret: existing.pollSecret,
        pollAfterMs: 1000,
      );
    }

    final requestId = newId();
    final pollSecret = base64UrlToken(secureRandomBytes(32));
    final code = confirmationCode(
      pairingTokenBytes: session.tokenBytes,
      requestId: requestId,
      fingerprintHex: _fingerprint,
    );
    final record = PairingRequestRecord(
      requestId: requestId,
      pollSecret: pollSecret,
      clientInstanceId: request.clientInstanceId,
      displayName: request.displayName,
      platform: request.platform,
      protocolVersion: request.protocolVersion,
      confirmationCode: code,
      requestedAt: _now(),
      state: PairingState.pendingApproval,
    );
    _requests[requestId] = record;
    _requestEvents.add(record.info);
    _logger.info('pairing: request received', fields: {'request': requestId});
    return PairRequestResponse(
      requestId: requestId,
      pollSecret: pollSecret,
      pollAfterMs: 1000,
    );
  }

  /// Approve a pending request. Creates the peer row (token hash only) and
  /// keeps the clear token in memory for exactly one status poll.
  Future<Peer> approve(String requestId) async {
    final record = _requests[requestId];
    if (record == null) throw const NotFoundError('pairing request not found');
    if (record.state != PairingState.pendingApproval) {
      throw const PairingFailedError();
    }
    final session = currentSession;
    if (session == null) throw const PairingFailedError(expired: true);

    final token = DeviceTokens.issue();
    final peer = Peer(
      id: record.clientInstanceId,
      name: record.displayName,
      kind: PeerKind.phone,
      roleOfPeer: PeerRole.guest,
      tokenHash: DeviceTokens.hash(token),
      lastSeen: _now().millisecondsSinceEpoch,
      protocolVersion: record.protocolVersion,
      createdAt: _now().millisecondsSinceEpoch,
    );
    await _peers.addPairedPeer(peer);

    _requests[requestId] = record.copyWith(
      state: PairingState.approved,
      issuedToken: token,
    );
    _requestEvents.add(_requests[requestId]!.info);
    // Single use: the QR/manual code cannot start another request.
    _session = null;
    _sessionEvents.add(null);
    _logger.info('pairing: approved', fields: {'peer': peer.id});
    return peer;
  }

  Future<void> reject(String requestId) async {
    final record = _requests[requestId];
    if (record == null) throw const NotFoundError('pairing request not found');
    if (record.state != PairingState.pendingApproval) return;
    _requests[requestId] =
        record.copyWith(state: PairingState.rejected, clearIssuedToken: true);
    _requestEvents.add(_requests[requestId]!.info);
    _logger.info('pairing: rejected', fields: {'request': requestId});
  }

  /// `GET /v1/pair/status` (`docs/05`). The token is returned exactly once.
  PairStatusResponse status(String requestId, String pollSecret) {
    final record = _requests[requestId];
    if (record == null) throw const PairingFailedError();
    if (!DeviceTokens.constantTimeEquals(record.pollSecret, pollSecret)) {
      _rateLimiter.recordFailure();
      throw const PairingFailedError();
    }
    if (record.state == PairingState.pendingApproval &&
        _now().isAfter(record.requestedAt.add(const Duration(minutes: 5)))) {
      _requests[requestId] = record.copyWith(state: PairingState.expired);
      return const PairStatusResponse(state: PairingState.expired);
    }
    if (record.state != PairingState.approved) {
      return PairStatusResponse(state: record.state);
    }
    if (record.collected || record.issuedToken == null) {
      return PairStatusResponse(
        state: PairingState.approved,
        deviceId: record.clientInstanceId,
        hostDeviceId: _hostDeviceId,
        hostName: _hostName,
        protocolVersion: FrameCodec.protocolVersion,
        alreadyCollected: true,
      );
    }
    final token = record.issuedToken!;
    _requests[requestId] = record.copyWith(
      collected: true,
      clearIssuedToken: true,
    );
    return PairStatusResponse(
      state: PairingState.approved,
      deviceId: record.clientInstanceId,
      deviceToken: token,
      hostDeviceId: _hostDeviceId,
      hostName: _hostName,
      protocolVersion: FrameCodec.protocolVersion,
    );
  }

  /// Expire old requests; called lazily by [pendingRequests]/HTTP handlers.
  void prune() {
    final now = _now();
    for (final entry in _requests.entries.toList()) {
      final r = entry.value;
      if (r.state == PairingState.pendingApproval &&
          now.isAfter(r.requestedAt.add(const Duration(minutes: 5)))) {
        _requests[entry.key] = r.copyWith(state: PairingState.expired);
      }
    }
    final s = _session;
    if (s != null && s.isExpiredAt(now)) {
      _session = null;
      _sessionEvents.add(null);
    }
  }

  Future<void> dispose() async {
    _session = null;
    await _sessionEvents.close();
    await _requestEvents.close();
  }
}

List<int>? _decodePairingToken(String token) {
  try {
    final normalized =
        base64Url.normalize(token.padRight((token.length + 3) & ~3, '='));
    final bytes = base64Url.decode(normalized);
    if (bytes.length != 20 && bytes.length != 32) return null;
    return bytes;
  } on FormatException {
    return null;
  }
}
