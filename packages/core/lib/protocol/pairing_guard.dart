import '../db/store_ops.dart';
import '../models/enums.dart';
import '../models/errors.dart';
import '../models/peer.dart';
import '../util/hashing.dart';
import '../util/logger.dart';
import '../services/peer_registry.dart';
import 'pairing_payload.dart';

/// 256-bit device tokens (`docs/08`): the phone keeps the token in secure
/// storage, the desktop stores only `sha256(token)`.
abstract final class DeviceTokens {
  static const int tokenBytes = 32;

  static String issue() => base64UrlToken(secureRandomBytes(tokenBytes));

  static String hash(String token) => tokenHashOf(token);

  /// Constant-time comparison for two hex strings.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

/// Bearer-token authentication for REST and WS upgrades (`docs/05`).
///
/// Resolves the sender identity from the token, never from client-claimed ids.
/// Missing/invalid token → 401; valid token of a revoked device → 403.
class TokenAuthenticator {
  TokenAuthenticator({required PeerRegistry peers, required Logger logger})
    : _peers = peers,
      _logger = logger;

  final PeerRegistry _peers;
  final Logger _logger;

  static String? bearerFrom(String? authorizationHeader) {
    if (authorizationHeader == null) return null;
    final match = RegExp(
      r'^Bearer\s+([A-Za-z0-9\-_\.]{16,200})$',
      caseSensitive: false,
    ).firstMatch(authorizationHeader.trim());
    return match?.group(1);
  }

  Future<Peer> authenticateHeader(String? authorizationHeader) async {
    final token = bearerFrom(authorizationHeader);
    if (token == null || token.isEmpty) {
      throw const UnauthorizedError();
    }
    return authenticateToken(token);
  }

  Future<Peer> authenticateToken(String token) async {
    final hash = DeviceTokens.hash(token);
    final peer = await _peers.findByTokenHash(hash);
    if (peer == null) {
      _logger.warn('auth: unknown token');
      throw const UnauthorizedError();
    }
    if (peer.tokenHash == null ||
        !DeviceTokens.constantTimeEquals(peer.tokenHash!, hash)) {
      throw const UnauthorizedError();
    }
    if (peer.isRevoked) {
      _logger.warn('auth: revoked device', fields: {'peer': peer.id});
      throw const ForbiddenError('this device was revoked; pair again');
    }
    return peer;
  }
}

/// Pairing abuse control: 5 failed token attempts in 60 s lock pairing for 60 s
/// (`PAIR-010`, `docs/05` §Abuse controls).
class PairingRateLimiter {
  PairingRateLimiter({
    DateTime Function()? now,
    this.maxFailures = 5,
    this.window = const Duration(seconds: 60),
    this.lockoutDuration = const Duration(seconds: 60),
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  final int maxFailures;
  final Duration window;
  final Duration lockoutDuration;

  final List<DateTime> _failures = <DateTime>[];
  DateTime? _lockedUntil;

  bool get isLocked {
    final until = _lockedUntil;
    if (until == null) return false;
    if (_now().isBefore(until)) return true;
    _lockedUntil = null;
    _failures.clear();
    return false;
  }

  Duration get remaining {
    if (!isLocked) return Duration.zero;
    return _lockedUntil!.difference(_now());
  }

  void recordFailure() {
    final now = _now();
    _failures.removeWhere((t) => now.difference(t) > window);
    _failures.add(now);
    if (_failures.length >= maxFailures) {
      _lockedUntil = now.add(lockoutDuration);
    }
  }

  void recordSuccess() {
    _failures.clear();
    _lockedUntil = null;
  }

  void reset() {
    _failures.clear();
    _lockedUntil = null;
  }

  /// Throw if locked (generic pairing_failed for callers).
  void check() {
    if (isLocked) {
      throw RateLimitedError(
        retryAfterSeconds: remaining.inSeconds.clamp(1, 3600),
      );
    }
  }
}

/// Strict wire models for the pairing HTTP endpoints (`docs/05` §Pairing).
class PairRequest {
  const PairRequest({
    required this.pairingToken,
    required this.clientInstanceId,
    required this.displayName,
    required this.platform,
    required this.protocolVersion,
  });

  final String pairingToken;
  final String clientInstanceId;
  final String displayName;
  final String platform;
  final int protocolVersion;

  Map<String, dynamic> toJson() => {
    'pairingToken': pairingToken,
    'clientInstanceId': clientInstanceId,
    'displayName': displayName,
    'platform': platform,
    'protocolVersion': protocolVersion,
  };

  static PairRequest fromJson(Map<String, dynamic> json) {
    String str(String key, {int max = 200}) {
      final v = json[key];
      if (v is! String || v.isEmpty || v.length > max) {
        throw ProtocolError('invalid $key');
      }
      return v;
    }

    final version = json['protocolVersion'];
    if (version is! int) throw const ProtocolError('invalid protocolVersion');
    return PairRequest(
      pairingToken: str('pairingToken', max: 100),
      clientInstanceId: str('clientInstanceId', max: 100),
      displayName: str('displayName', max: 100),
      platform: str('platform', max: 40),
      protocolVersion: version,
    );
  }
}

class PairRequestResponse {
  const PairRequestResponse({
    required this.requestId,
    required this.pollSecret,
    required this.pollAfterMs,
  });

  final String requestId;
  final String pollSecret;
  final int pollAfterMs;

  Map<String, dynamic> toJson() => {
    'requestId': requestId,
    'pollSecret': pollSecret,
    'pollAfterMs': pollAfterMs,
  };

  static PairRequestResponse fromJson(Map<String, dynamic> json) {
    final requestId = json['requestId'];
    final pollSecret = json['pollSecret'];
    final pollAfterMs = json['pollAfterMs'];
    if (requestId is! String ||
        pollSecret is! String ||
        pollAfterMs is! int ||
        pollAfterMs < 0) {
      throw const ProtocolError('malformed pairing response');
    }
    return PairRequestResponse(
      requestId: requestId,
      pollSecret: pollSecret,
      pollAfterMs: pollAfterMs,
    );
  }
}

class PairStatusResponse {
  const PairStatusResponse({
    required this.state,
    this.deviceId,
    this.deviceToken,
    this.hostDeviceId,
    this.hostName,
    this.protocolVersion,
    this.alreadyCollected = false,
  });

  final PairingState state;
  final String? deviceId;
  final String? deviceToken;
  final String? hostDeviceId;
  final String? hostName;
  final int? protocolVersion;

  /// True when the one-time secrets were already handed out (`already_collected`).
  final bool alreadyCollected;

  Map<String, dynamic> toJson() => {
    'state': state.wire,
    if (deviceId != null) 'deviceId': deviceId,
    if (deviceToken != null) 'deviceToken': deviceToken,
    if (hostDeviceId != null) 'hostDeviceId': hostDeviceId,
    if (hostName != null) 'hostName': hostName,
    if (protocolVersion != null) 'protocolVersion': protocolVersion,
    if (alreadyCollected) 'alreadyCollected': true,
  };

  static PairStatusResponse fromJson(Map<String, dynamic> json) {
    final state = json['state'];
    if (state is! String) throw const ProtocolError('invalid pairing state');
    final PairingState parsed;
    try {
      parsed = PairingState.parse(state);
    } on FormatException {
      throw const ProtocolError('invalid pairing state');
    }
    String? opt(String key) {
      final v = json[key];
      if (v == null) return null;
      if (v is! String) throw ProtocolError('invalid $key');
      return v;
    }

    final version = json['protocolVersion'];
    return PairStatusResponse(
      state: parsed,
      deviceId: opt('deviceId'),
      deviceToken: opt('deviceToken'),
      hostDeviceId: opt('hostDeviceId'),
      hostName: opt('hostName'),
      protocolVersion: version is int ? version : null,
      alreadyCollected: json['alreadyCollected'] == true,
    );
  }
}

/// Information the desktop approval card shows (`PAIR-003`).
class PairingRequestInfo {
  const PairingRequestInfo({
    required this.requestId,
    required this.displayName,
    required this.platform,
    required this.protocolVersion,
    required this.confirmationCode,
    required this.requestedAt,
    this.state = PairingState.pendingApproval,
  });

  final String requestId;
  final String displayName;
  final String platform;
  final int protocolVersion;

  /// 4-digit code both screens must show (`docs/05` §Confirmation code).
  final String confirmationCode;
  final DateTime requestedAt;
  final PairingState state;

  PairingRequestInfo copyWith({PairingState? state}) => PairingRequestInfo(
    requestId: requestId,
    displayName: displayName,
    platform: platform,
    protocolVersion: protocolVersion,
    confirmationCode: confirmationCode,
    requestedAt: requestedAt,
    state: state ?? this.state,
  );
}

/// HTTP error body (`docs/05` §Error format).
class ApiError {
  const ApiError({
    required this.code,
    required this.message,
    this.requestId,
    this.retryable = false,
  });

  final String code;
  final String message;
  final String? requestId;
  final bool retryable;

  Map<String, dynamic> toJson() => {
    'error': {
      'code': code,
      'message': message,
      if (requestId != null) 'requestId': requestId,
      'retryable': retryable,
    },
  };

  static ApiError fromJson(Map<String, dynamic> json) {
    final e = json['error'];
    if (e is! Map) throw const ProtocolError('malformed error body');
    final code = e['code'];
    final message = e['message'];
    if (code is! String || message is! String) {
      throw const ProtocolError('malformed error body');
    }
    return ApiError(
      code: code,
      message: message,
      requestId: e['requestId'] is String ? e['requestId'] as String : null,
      retryable: e['retryable'] == true,
    );
  }
}

/// Read access used by the pairing endpoints to check token single-use.
extension PairingTokenLookup on AppDatabaseStub {
  // Marker extension kept empty; the real implementation lives in
  // PairingService and uses the in-memory session state.
}

/// Marker type only so the extension above documents intent without exposing
/// internals; never instantiated.
abstract final class AppDatabaseStub {
  const AppDatabaseStub();
}
