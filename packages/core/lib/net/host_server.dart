import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../db/database.dart';
import '../models/enums.dart';
import '../models/errors.dart';
import '../protocol/close_codes.dart';
import '../protocol/frames.dart';
import '../protocol/pairing_guard.dart';
import '../services/pairing_service.dart';
import '../services/peer_registry.dart';
import '../tls/tls_identity.dart';
import '../util/logger.dart';
import '../sync/change_bus.dart';
import '../sync/sync_engine.dart';
import 'peer_session.dart';

/// Desktop host: HTTPS pairing endpoints + authenticated WSS sessions
/// (`docs/05`). Only reaches the network when a pairing session is open or at
/// least one peer is paired; the runtime owns that lifecycle (`SEC-007`).
class HostServer {
  HostServer({
    required TlsIdentity identity,
    required AppDatabase db,
    required SyncEngine sync,
    required ChangeBus bus,
    required PeerRegistry peers,
    required Logger logger,
    required String deviceId,
    required String deviceName,
    required String appVersion,
    required String Function() versionName,
    required List<String> Function() localHosts,
    int preferredPort = 47321,
  }) : _identity = identity,
       _db = db,
       _sync = sync,
       _bus = bus,
       _peers = peers,
       _logger = logger,
       _deviceId = deviceId,
       _deviceName = deviceName,
       _appVersion = appVersion,
       _versionName = versionName,
       _localHosts = localHosts,
       _preferredPort = preferredPort {
    pairing = PairingService(
      peers: peers,
      logger: logger,
      hostDeviceId: deviceId,
      hostName: deviceName,
      fingerprint: identity.fingerprint,
      hostsProvider: () => _localHosts(),
      portProvider: () => _port,
      now: DateTime.now,
    );
    _revokedSub = peers.revokedStream.listen(_onPeerRevoked);
  }

  final TlsIdentity _identity;
  final AppDatabase _db;
  final SyncEngine _sync;
  final ChangeBus _bus;
  final PeerRegistry _peers;
  final Logger _logger;
  final String _deviceId;
  final String _deviceName;
  final String _appVersion;
  final String Function() _versionName;
  final List<String> Function() _localHosts;
  final int _preferredPort;

  late final PairingService pairing;
  StreamSubscription<String>? _revokedSub;
  HttpServer? _server;
  int _port = 0;
  final Map<String, PeerSession> _sessions = <String, PeerSession>{};
  final StreamController<Set<String>> _sessionsController =
      StreamController<Set<String>>.broadcast();
  bool _stopping = false;

  int get port => _port;
  bool get isRunning => _server != null;
  Set<String> get connectedPeerIds => Set<String>.unmodifiable(_sessions.keys);

  /// Emits the set of connected peer ids after every change.
  Stream<Set<String>> get sessions => _sessionsController.stream;

  static const int _maxBodyBytes = 64 * 1024;

  /// Bind, trying the preferred port and the next 20 (`docs/05`).
  Future<int> start() async {
    if (_server != null) return _port;
    _stopping = false;
    _revokedSub ??= _peers.revokedStream.listen(_onPeerRevoked);
    Object? lastError;
    for (var attempt = 0; attempt < 20; attempt++) {
      final candidate = _preferredPort + attempt;
      try {
        final server = await HttpServer.bindSecure(
          InternetAddress.anyIPv4,
          candidate,
          _identity.serverContext(),
        );
        server.autoCompress = false;
        _server = server;
        _port = server.port;
        server.listen(_handleRequest);
        _logger.info('host: listening', fields: {'port': _port});
        return _port;
      } on SocketException catch (e) {
        lastError = e;
      } on Object catch (e) {
        lastError = e;
        break;
      }
    }
    throw NetworkError('could not bind the desktop port', cause: lastError);
  }

  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    for (final session in _sessions.values.toList()) {
      await session.dispose();
    }
    _sessions.clear();
    _emitSessions();
    await _server?.close(force: true);
    _server = null;
    _logger.info('host: stopped');
  }

  Future<void> _handleRequest(HttpRequest request) async {
    request.response.headers
      ..set(HttpHeaders.cacheControlHeader, 'no-store')
      ..set('X-Content-Type-Options', 'nosniff');
    try {
      if (!_isAllowedRemote(request)) {
        await _writeError(request, const ForbiddenError());
        return;
      }
      final path = request.uri.path;
      if (request.method == 'GET' && path == '/v1/health') {
        await _writeJson(request, HttpStatus.ok, <String, dynamic>{
          'app': 'twindrop',
          'protocolVersion': FrameCodec.protocolVersion,
          'version': _versionName(),
        });
        return;
      }
      if (request.method == 'POST' && path == '/v1/pair/request') {
        await _handlePairRequest(request);
        return;
      }
      if (request.method == 'GET' && path == '/v1/pair/status') {
        await _handlePairStatus(request);
        return;
      }
      if (request.method == 'POST' && path == '/v1/devices/self/revoke') {
        await _handleSelfRevoke(request);
        return;
      }
      if (path == '/v1/ws') {
        await _handleWebSocket(request);
        return;
      }
      await _writeError(request, const NotFoundError());
    } on TwinDropError catch (e) {
      await _writeError(request, e);
    } on Object catch (e) {
      _logger.error('host: request failed', fields: {'error': e.runtimeType});
      await _writeError(request, const InternalError('internal error'));
    }
  }

  bool _isAllowedRemote(HttpRequest request) {
    final address = request.connectionInfo?.remoteAddress;
    if (address == null) return true;
    if (address.isLoopback) return true;
    if (address.type == InternetAddressType.IPv6) {
      final a = address.address.toLowerCase();
      if (a == '::1' ||
          a.startsWith('fe80:') ||
          a.startsWith('fc') ||
          a.startsWith('fd')) {
        return true;
      }
      if (a.startsWith('::ffff:')) {
        return _isPrivateIpv4(a.substring(7));
      }
      return false;
    }
    return _isPrivateIpv4(address.address);
  }

  static bool _isPrivateIpv4(String address) {
    final parts = address.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((p) => p == null)) return false;
    final a = parts[0]!;
    final b = parts[1]!;
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    if (a == 169 && b == 254) return true;
    if (a == 127) return true;
    return false;
  }

  Future<void> _handlePairRequest(HttpRequest request) async {
    final body = await _readBody(request);
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException('not an object');
      json = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const ProtocolError('malformed pairing request');
    }
    final pairRequest = PairRequest.fromJson(json);
    final response = await pairing.handleRequest(pairRequest);
    await _writeJson(request, HttpStatus.accepted, response.toJson());
  }

  Future<void> _handlePairStatus(HttpRequest request) async {
    final requestId = request.uri.queryParameters['requestId'] ?? '';
    final secret = request.headers.value('X-Poll-Secret') ?? '';
    if (requestId.isEmpty || secret.isEmpty) {
      throw const PairingFailedError();
    }
    pairing.prune();
    final response = pairing.status(requestId, secret);
    await _writeJson(request, HttpStatus.ok, response.toJson());
  }

  Future<void> _handleSelfRevoke(HttpRequest request) async {
    final authenticator = TokenAuthenticator(peers: _peers, logger: _logger);
    final peer = await authenticator.authenticateHeader(
      request.headers.value(HttpHeaders.authorizationHeader),
    );
    await _peers.revoke(peer.id);
    await _closePeerSocket(
      peer.id,
      CloseCodes.forbidden,
      CloseCodes.reasonRevoked,
    );
    await _writeJson(request, HttpStatus.ok, <String, dynamic>{'ok': true});
  }

  Future<void> _handleWebSocket(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      throw const ProtocolError('expected a WebSocket upgrade');
    }
    final authenticator = TokenAuthenticator(peers: _peers, logger: _logger);
    final peer = await authenticator.authenticateHeader(
      request.headers.value(HttpHeaders.authorizationHeader),
    );

    final WebSocket socket;
    try {
      socket = await WebSocketTransformer.upgrade(request);
    } on Object {
      throw const InternalError('could not upgrade the connection');
    }

    // One session per device: the newest wins, the old one is closed 4409.
    await _closePeerSocket(
      peer.id,
      CloseCodes.duplicateSession,
      CloseCodes.reasonDuplicate,
    );

    late final PeerSession session;
    session = PeerSession(
      db: _db,
      sync: _sync,
      bus: _bus,
      peers: _peers,
      logger: _logger,
      localDeviceId: _deviceId,
      localDeviceName: _deviceName,
      localKind: PeerKind.desktop,
      appVersion: _appVersion,
      peerId: peer.id,
      sendRaw: (raw) {
        if (socket.readyState == WebSocket.open) socket.add(raw);
      },
      closeSocket: (code, reason) => socket.close(code, reason),
      isHost: true,
      onEnded: (s, code, reason) {
        if (identical(_sessions[peer.id], s)) {
          _sessions.remove(peer.id);
          _emitSessions();
        }
      },
    );
    _sessions[peer.id] = session;
    _emitSessions();
    socket.listen(
      (data) {
        if (data is String) {
          session.handleMessage(data);
        } else if (data is List<int>) {
          // Binary frames are not part of the protocol.
          socket.close(CloseCodes.internal, CloseCodes.reasonInternal);
        }
      },
      onDone: () =>
          session.handleSocketClosed(socket.closeCode, socket.closeReason),
      onError: (Object _) =>
          session.handleSocketClosed(socket.closeCode, socket.closeReason),
      cancelOnError: true,
    );
    await session.startHost();
    _logger.info('host: session open', fields: {'peer': peer.id});
  }

  Future<void> _closePeerSocket(String peerId, int code, String reason) async {
    final existing = _sessions.remove(peerId);
    if (existing == null) return;
    // The close code must reach the peer: a revoked device has to see 4403.
    await existing.dispose(code: code, reason: reason);
    _emitSessions();
  }

  /// Final teardown: unlike [stop], this closes the pairing streams and the
  /// revoked subscription, so the object cannot be restarted.
  Future<void> dispose() async {
    await stop();
    await _revokedSub?.cancel();
    _revokedSub = null;
    await pairing.dispose();
    if (!_sessionsController.isClosed) await _sessionsController.close();
  }

  void _onPeerRevoked(String peerId) {
    unawaited(
      _closePeerSocket(peerId, CloseCodes.forbidden, CloseCodes.reasonRevoked),
    );
  }

  void _emitSessions() {
    if (!_sessionsController.isClosed) {
      _sessionsController.add(Set<String>.unmodifiable(_sessions.keys));
    }
  }

  Future<String> _readBody(HttpRequest request) async {
    final chunks = <int>[];
    var total = 0;
    await for (final chunk in request) {
      total += chunk.length;
      if (total > _maxBodyBytes) {
        throw const PayloadTooLargeError('request body too large');
      }
      chunks.addAll(chunk);
    }
    try {
      return utf8.decode(chunks);
    } on FormatException {
      throw const ProtocolError('body is not UTF-8');
    }
  }

  Future<void> _writeJson(
    HttpRequest request,
    int status,
    Map<String, dynamic> body,
  ) async {
    final response = request.response;
    response.statusCode = status;
    response.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _writeError(HttpRequest request, TwinDropError error) async {
    final response = request.response;
    response.statusCode = error.httpStatus;
    response.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    response.write(
      jsonEncode(
        ApiError(
          code: error.code,
          message: error.message,
          retryable: error.retryable,
        ).toJson(),
      ),
    );
    await response.close();
  }
}
