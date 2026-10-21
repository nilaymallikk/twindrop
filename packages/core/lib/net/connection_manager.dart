import 'dart:async';
import 'dart:io';
import 'dart:math';

import '../db/database.dart';
import '../models/enums.dart';
import '../models/errors.dart';
import '../models/peer.dart';
import '../protocol/close_codes.dart';
import '../services/peer_registry.dart';
import '../services/stores.dart';
import '../tls/tls_identity.dart';
import '../util/logger.dart';
import '../sync/change_bus.dart';
import '../sync/sync_engine.dart';
import 'discovery.dart';
import 'peer_session.dart';

/// Phone-side connection manager (`PAIR-006`, `PAIR-007`, `SYNC-008`).
///
/// Tries the last-known address, then mDNS, then a manually configured address.
/// Every attempt verifies the full pin; a mismatch is a blocking error that is
/// never retried automatically (`docs/08`). Backoff is bounded 1→30 s with
/// ±20% jitter and is reset by a network change or [retryNow].
class ConnectionManager {
  ConnectionManager({
    required AppDatabase db,
    required SyncEngine sync,
    required ChangeBus bus,
    required PeerRegistry peers,
    required TokenStore tokenStore,
    required Logger logger,
    required String deviceId,
    required String deviceName,
    required PeerKind deviceKind,
    required String appVersion,
    MdnsDiscovery? discovery,
    MulticastLock? multicastLock,
    CoreNotifier? notifier,
    Random? random,
    this.pauseOnStart = false,
  }) : _db = db,
       _sync = sync,
       _bus = bus,
       _peers = peers,
       _tokenStore = tokenStore,
       _logger = logger,
       _deviceId = deviceId,
       _deviceName = deviceName,
       _deviceKind = deviceKind,
       _appVersion = appVersion,
       _discovery = discovery,
       _multicastLock = multicastLock ?? NoopMulticastLock(),
       _notifier = notifier ?? NoopNotifier(),
       _random = random ?? Random();

  final AppDatabase _db;
  final SyncEngine _sync;
  final ChangeBus _bus;
  final PeerRegistry _peers;
  final TokenStore _tokenStore;
  final Logger _logger;
  final String _deviceId;
  final String _deviceName;
  final PeerKind _deviceKind;
  final String _appVersion;
  final MdnsDiscovery? _discovery;
  final MulticastLock _multicastLock;
  final CoreNotifier _notifier;
  final Random _random;
  bool pauseOnStart;

  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<Map<String, ConnectionStatus>> _peerStatesController =
      StreamController<Map<String, ConnectionStatus>>.broadcast();
  final StreamController<String?> _errorController =
      StreamController<String?>.broadcast();

  ConnectionStatus _status = ConnectionStatus.unpaired;
  final Map<String, ConnectionStatus> _peerStates =
      <String, ConnectionStatus>{};
  bool _stopped = true;
  bool _paused = false;
  bool _pinnedFailure = false;
  int _backoffIndex = 0;
  Completer<void>? _wake;
  PeerSession? _session;
  String? _manualHost;
  int? _manualPort;

  static const List<int> _backoffSeconds = <int>[1, 2, 4, 8, 15, 30];

  ConnectionStatus get status => _status;
  ConnectionStatus? statusFor(String peerId) => _peerStates[peerId];
  bool get isPaused => _paused;

  /// Ids of the peers with a live, authenticated session right now.
  Set<String> get connectedPeerIds =>
      _session == null ? const <String>{} : <String>{_session!.peerId};

  int get backoffSeconds =>
      _backoffSeconds[_backoffIndex.clamp(0, _backoffSeconds.length - 1)];

  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<Map<String, ConnectionStatus>> get peerStatesStream =>
      _peerStatesController.stream;
  Stream<String?> get errorStream => _errorController.stream;

  /// Override the address used before mDNS (manual pairing).
  void setManualAddress(String? host, int? port) {
    _manualHost = host;
    _manualPort = port;
    retryNow();
  }

  Future<void> start() async {
    if (!_stopped) return;
    _stopped = false;
    _paused = pauseOnStart;
    final peers = await _peers.active();
    if (_paused) {
      _setStatus(ConnectionStatus.paused);
      return;
    }
    if (peers.isEmpty) _setStatus(ConnectionStatus.unpaired);
    unawaited(_loop());
  }

  /// Stop retrying and close the live session (Pause / app closing without a
  /// service).
  Future<void> stop() async {
    _stopped = true;
    await _endSession();
    _wake?.complete();
    _wake = null;
  }

  Future<void> pause() async {
    if (_paused) return;
    _paused = true;
    await _endSession();
    _wake?.complete();
    _setStatus(ConnectionStatus.paused);
  }

  Future<void> resume() async {
    if (!_paused) {
      retryNow();
      return;
    }
    _paused = false;
    _backoffIndex = 0;
    _setStatus(ConnectionStatus.searching);
    if (_stopped) {
      _stopped = false;
      unawaited(_loop());
    } else {
      _wake?.complete();
    }
  }

  /// Immediate retry on Wi-Fi change, foreground, or user action.
  void retryNow() {
    _backoffIndex = 0;
    _wake?.complete();
    _wake = null;
  }

  Future<void> _loop() async {
    while (!_stopped && !_paused) {
      final peers = await _peers.active();
      if (peers.isEmpty) {
        _setStatus(ConnectionStatus.unpaired);
        await _sleepBackoff();
        continue;
      }
      final peer = peers.first;
      if (peer.isRevoked) {
        _setStatus(ConnectionStatus.removed);
        await _sleepBackoff();
        continue;
      }
      final token = await _tokenStore.read(
        peer.tokenRef ?? peerTokenRef(peer.id),
      );
      if (token == null || token.isEmpty) {
        _logger.warn('conn: no token for peer', fields: {'peer': peer.id});
        _setStatus(ConnectionStatus.unpaired);
        await _sleepBackoff();
        continue;
      }
      final locator = await _resolve(peer);
      if (locator == null) {
        _setStatus(ConnectionStatus.searching);
        await _sleepBackoff();
        continue;
      }
      _setStatus(ConnectionStatus.connecting);
      final session = await _connect(peer, token, locator);
      if (session == null) {
        if (_pinnedFailure) {
          // Blocking: never retry a pin mismatch automatically.
          _setStatus(ConnectionStatus.offline);
          await _sleepBackoff(forceLong: true);
          continue;
        }
        _setStatus(ConnectionStatus.offline);
        await _sleepBackoff();
        continue;
      }
      _session = session;
      _backoffIndex = 0;
      try {
        await session.readyFuture.timeout(const Duration(seconds: 6));
        _setStatus(ConnectionStatus.connected);
        await _notifier.onConnectionChanged(ConnectionStatus.connected);
      } on TimeoutException {
        _logger.warn('conn: handshake timeout');
        await session.dispose();
        _setStatus(ConnectionStatus.offline);
        continue;
      }
      await _waitSessionEnd(session);
      _session = null;
      if (_sessionEndCode == CloseCodes.forbidden) {
        _setStatus(ConnectionStatus.removed);
        await _notifier.onConnectionChanged(ConnectionStatus.removed);
        return;
      }
      if (_sessionEndCode == CloseCodes.unauthorized) {
        _setStatus(ConnectionStatus.unpaired);
        return;
      }
      _setStatus(ConnectionStatus.searching);
      await _notifier.onConnectionChanged(ConnectionStatus.searching);
      await _sleepBackoff();
    }
  }

  int? _sessionEndCode;
  Completer<void>? _sessionEnd;

  Future<void> _waitSessionEnd(PeerSession session) async {
    _sessionEnd ??= Completer<void>();
    await _sessionEnd!.future;
    _sessionEnd = null;
  }

  Future<PeerSession?> _connect(
    Peer peer,
    String token,
    ({String host, int port}) locator,
  ) async {
    final pin = peer.certFp;
    if (pin == null || pin.length != 64) {
      _logger.warn('conn: peer has no valid pin', fields: {'peer': peer.id});
      _setStatus(ConnectionStatus.unpaired);
      return null;
    }
    final attackHost = locator.host;
    final port = locator.port;
    final http = TlsIdentity.pinnedHttpClient(pin);
    _pinnedFailure = false;
    _sessionEndCode = null;
    try {
      final healthUri = Uri(
        scheme: 'https',
        host: attackHost,
        port: port,
        path: '/v1/health',
      );
      final request = await http
          .getUrl(healthUri)
          .timeout(const Duration(seconds: 5));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      await response.drain<void>();
      if (response.statusCode != 200) {
        throw NetworkError('health check failed (${response.statusCode})');
      }

      final wsUri = Uri(
        scheme: 'wss',
        host: attackHost,
        port: port,
        path: '/v1/ws',
      );
      final socket = await WebSocket.connect(
        wsUri.toString(),
        customClient: http,
        headers: <String, dynamic>{
          HttpHeaders.authorizationHeader: 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 6));

      late final PeerSession session;
      final ended = Completer<void>();
      session = PeerSession(
        db: _db,
        sync: _sync,
        bus: _bus,
        peers: _peers,
        logger: _logger,
        localDeviceId: _deviceId,
        localDeviceName: _deviceName,
        localKind: _deviceKind,
        appVersion: _appVersion,
        peerId: peer.id,
        sendRaw: (raw) {
          if (socket.readyState == WebSocket.open) socket.add(raw);
        },
        closeSocket: (code, reason) => socket.close(code, reason),
        isHost: false,
        onEnded: (s, code, reason) {
          _sessionEndCode = code;
          if (!ended.isCompleted) ended.complete();
        },
      );
      socket.listen(
        (data) {
          if (data is String) {
            session.handleMessage(data);
          } else {
            socket.close(CloseCodes.internal, CloseCodes.reasonInternal);
          }
        },
        onDone: () =>
            session.handleSocketClosed(socket.closeCode, socket.closeReason),
        onError: (Object _) =>
            session.handleSocketClosed(socket.closeCode, socket.closeReason),
        cancelOnError: true,
      );
      unawaited(session.startClient());
      await _peers.touch(peer.id, host: attackHost, port: port);
      _logger.info('conn: session open', fields: {'peer': peer.id});
      unawaited(ended.future.whenComplete(() => http.close(force: true)));
      return session;
    } on HandshakeException catch (e) {
      _pinnedFailure = true;
      _logger.warn(
        'conn: certificate rejected',
        fields: {'peer': peer.id, 'error': e.runtimeType},
      );
      _errorController.add(const CertificateMismatchError().message);
      http.close(force: true);
      return null;
    } on TlsException catch (e) {
      _pinnedFailure = true;
      _logger.warn('conn: TLS failed', fields: {'error': e.runtimeType});
      http.close(force: true);
      return null;
    } on SocketException catch (e) {
      _logger.debug('conn: socket failure', fields: {'error': e.runtimeType});
      http.close(force: true);
      return null;
    } on TimeoutException {
      _logger.debug('conn: timeout');
      http.close(force: true);
      return null;
    } on Object catch (e) {
      _logger.debug('conn: dial failed', fields: {'error': e.runtimeType});
      http.close(force: true);
      return null;
    }
  }

  Future<void> _endSession() async {
    final session = _session;
    _session = null;
    _sessionEndCode = null;
    if (session != null) {
      await session.dispose();
    }
    if (_sessionEnd != null && !_sessionEnd!.isCompleted) {
      _sessionEnd!.complete();
    }
  }

  Future<({String host, int port})?> _resolve(Peer peer) async {
    if (_manualHost != null && _manualPort != null) {
      return (host: _manualHost!, port: _manualPort!);
    }
    if (peer.lastHost != null && peer.lastPort != null) {
      return (host: peer.lastHost!, port: peer.lastPort!);
    }
    final discovery = _discovery;
    if (discovery == null) return null;
    await _multicastLock.acquire();
    try {
      final found = await discovery.find(expectedPin: peer.certFp);
      if (found == null) return null;
      return (host: found.host, port: found.port);
    } finally {
      await _multicastLock.release();
    }
  }

  Future<void> _sleepBackoff({bool forceLong = false}) async {
    if (_stopped || _paused) return;
    final base = forceLong
        ? _backoffSeconds.last
        : _backoffSeconds[_backoffIndex.clamp(0, _backoffSeconds.length - 1)];
    if (!forceLong) {
      _backoffIndex = min(_backoffIndex + 1, _backoffSeconds.length - 1);
    }
    final jitter = 1 + (_random.nextDouble() * 0.4 - 0.2);
    final delay = Duration(milliseconds: (base * 1000 * jitter).round());
    _wake = Completer<void>();
    try {
      await _wake!.future.timeout(delay, onTimeout: () {});
    } on Object {
      // wake or timeout
    } finally {
      _wake = null;
    }
  }

  /// Phone-initiated unpair (`PAIR-009`): asks the desktop to revoke when
  /// reachable, then deletes the token and the peer bookkeeping.
  Future<void> unpair() async {
    final peers = await _peers.active();
    for (final peer in peers) {
      final token = await _tokenStore.read(peerTokenRef(peer.id));
      if (token != null && peer.lastHost != null && peer.lastPort != null) {
        final client = TlsIdentity.pinnedHttpClient(peer.certFp!);
        try {
          final uri = Uri(
            scheme: 'https',
            host: peer.lastHost!,
            port: peer.lastPort!,
            path: '/v1/devices/self/revoke',
          );
          final req = await client.postUrl(uri);
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
          final res = await req.close().timeout(const Duration(seconds: 4));
          await res.drain<void>();
        } on Object {
          // Offline is fine: the desktop can revoke later.
        } finally {
          client.close(force: true);
        }
      }
      await _tokenStore.delete(peerTokenRef(peer.id));
      await _peers.remove(peer.id);
    }
    await stop();
    _setStatus(ConnectionStatus.unpaired);
  }

  void _setStatus(ConnectionStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  Future<void> dispose() async {
    await stop();
    await _statusController.close();
    await _peerStatesController.close();
    await _errorController.close();
  }
}
