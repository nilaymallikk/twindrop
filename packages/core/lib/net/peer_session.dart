import 'dart:async';
import 'dart:convert';

import '../db/database.dart';
import '../models/enums.dart';
import '../models/errors.dart';
import '../protocol/close_codes.dart';
import '../protocol/frames.dart';
import '../services/peer_registry.dart';
import '../sync/change_bus.dart';
import '../sync/sync_engine.dart';
import '../util/logger.dart';

/// One authenticated WebSocket session with one peer (`docs/05` §Session).
///
/// The class is transport-agnostic: the host and the phone both run this exact
/// code, which keeps one protocol implementation. After the handshake the
/// change log is authoritative: `notify` triggers a `pull`; `changes` pages are
/// applied atomically and acknowledged; `ack` drives the Delivered state.
class PeerSession {
  PeerSession({
    required AppDatabase db,
    required SyncEngine sync,
    required ChangeBus bus,
    required PeerRegistry peers,
    required Logger logger,
    required String localDeviceId,
    required String localDeviceName,
    required PeerKind localKind,
    required String appVersion,
    required this.peerId,
    required void Function(String raw) sendRaw,
    required Future<void> Function(int code, String reason) closeSocket,
    required this.isHost,
    required void Function(PeerSession session, int? code, String? reason)
    onEnded,
    int Function()? nowMs,
  }) : _db = db,
       _sync = sync,
       _bus = bus,
       _peers = peers,
       _logger = logger,
       _localDeviceId = localDeviceId,
       _localDeviceName = localDeviceName,
       _localKind = localKind,
       _appVersion = appVersion,
       _sendRaw = sendRaw,
       _closeSocket = closeSocket,
       _onEnded = onEnded,
       _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AppDatabase _db;
  final SyncEngine _sync;
  final ChangeBus _bus;
  final PeerRegistry _peers;
  final Logger _logger;
  final String _localDeviceId;
  final String _localDeviceName;
  final PeerKind _localKind;
  final String _appVersion;
  final String peerId;
  final bool isHost;
  final void Function(String raw) _sendRaw;
  final Future<void> Function(int code, String reason) _closeSocket;
  final void Function(PeerSession session, int? code, String? reason) _onEnded;
  final int Function() _nowMs;

  StreamSubscription<int>? _busSub;
  Timer? _handshakeTimer;
  Timer? _pingTimer;
  bool _ready = false;
  final Completer<void> _readyCompleter = Completer<void>();
  bool _closed = false;
  bool _pulling = false;
  bool _pullQueued = false;
  int _lastInbound = 0;
  int _lastPong = 0;
  String peerName = '';
  PeerKind? peerKind;

  static const Duration handshakeTimeout = Duration(seconds: 5);
  static const Duration pingInterval = Duration(seconds: 15);
  static const Duration deadAfter = Duration(seconds: 30);

  bool get isReady => _ready;

  /// Completes once the handshake finished in either direction.
  Future<void> get readyFuture => _readyCompleter.future;
  bool get isClosed => _closed;

  /// Host side: wait for `hello`, then send `ready` and pull.
  Future<void> startHost() async {
    _startTimers(expectsHandshake: true);
    // The host speaks first only after the client's hello, per the protocol.
  }

  /// Client side: send `hello` immediately, then wait for `ready`.
  Future<void> startClient() async {
    _startTimers(expectsHandshake: true);
    await _send(
      HelloFrame(
        deviceId: _localDeviceId,
        name: _localDeviceName,
        kind: _localKind,
        appVersion: _appVersion,
      ),
    );
  }

  void _startTimers({required bool expectsHandshake}) {
    _lastInbound = _nowMs();
    _lastPong = _nowMs();
    if (expectsHandshake) {
      _handshakeTimer = Timer(handshakeTimeout, () {
        if (!_ready) {
          _logger.warn('ws: handshake timeout', fields: {'peer': peerId});
          _close(CloseCodes.upgradeRequired, CloseCodes.reasonUpgrade);
        }
      });
    }
    _pingTimer = Timer.periodic(pingInterval, (_) {
      if (_closed) return;
      final now = _nowMs();
      if (now - _lastInbound > deadAfter.inMilliseconds) {
        _logger.warn('ws: peer silent, closing', fields: {'peer': peerId});
        _close(CloseCodes.internal, CloseCodes.reasonInternal);
        return;
      }
      _send(PingFrame(ts: now));
    });
  }

  /// Feed one raw text frame from the socket. Never throws.
  Future<void> handleMessage(String raw) async {
    if (_closed) return;
    _lastInbound = _nowMs();
    Frame frame;
    try {
      frame = FrameCodec.decode(raw);
    } on PayloadTooLargeError {
      await _close(CloseCodes.internal, CloseCodes.reasonInternal);
      return;
    } on UnsupportedVersionError {
      await _close(CloseCodes.upgradeRequired, CloseCodes.reasonUpgrade);
      return;
    } on ProtocolError {
      // A malformed single frame is not fatal; log the category only.
      _logger.warn('ws: malformed frame', fields: {'peer': peerId});
      return;
    }

    try {
      await _handleFrame(frame);
    } on UnsupportedVersionError {
      await _close(CloseCodes.upgradeRequired, CloseCodes.reasonUpgrade);
    } on TwinDropError catch (e) {
      _logger.warn(
        'ws: frame failed',
        fields: {'peer': peerId, 'code': e.code},
      );
    } on Object catch (e) {
      _logger.warn(
        'ws: unexpected frame failure',
        fields: {'peer': peerId, 'error': e.runtimeType},
      );
    }
  }

  Future<void> _handleFrame(Frame frame) async {
    switch (frame) {
      case HelloFrame():
        if (!isHost) return;
        if (frame.v != FrameCodec.protocolVersion) {
          throw const UnsupportedVersionError('protocol version mismatch');
        }
        if (frame.deviceId != peerId) {
          await _close(CloseCodes.unauthorized, CloseCodes.reasonUnauthorized);
          return;
        }
        peerName = frame.name;
        peerKind = frame.kind;
        if (!_ready) {
          _handshakeTimer?.cancel();
          _ready = true;
          if (!_readyCompleter.isCompleted) _readyCompleter.complete();
          await _peers.touch(peerId);
          final seq = await _sync.localSeq();
          await _send(
            ReadyFrame(
              deviceId: _localDeviceId,
              name: _localDeviceName,
              seq: seq,
              serverTime: _nowMs(),
            ),
          );
          _busSub ??= _bus.stream.listen((_) => _notifyPeer());
          await _pull();
        }
      case ReadyFrame():
        if (isHost) return;
        if (frame.v != FrameCodec.protocolVersion) {
          throw const UnsupportedVersionError('protocol version mismatch');
        }
        if (frame.deviceId != peerId) {
          throw const ProtocolError('peer identity changed');
        }
        peerName = frame.name;
        peerKind = PeerKind.desktop;
        _handshakeTimer?.cancel();
        _ready = true;
        if (!_readyCompleter.isCompleted) _readyCompleter.complete();
        await _peers.touch(peerId);
        _busSub ??= _bus.stream.listen((_) => _notifyPeer());
        await _pull();
      case PullFrame():
        await _servePull(frame);
      case ChangesFrame():
        final result = await _sync.applyPage(
          fromPeerId: peerId,
          page: frame.page,
        );
        await _send(AckFrame(seq: frame.page.next));
        _logger.debug(
          'ws: page applied',
          fields: {
            'peer': peerId,
            'applied': result.applied,
            'more': frame.page.more,
          },
        );
        if (frame.page.more) {
          await _send(
            PullFrame(
              after: frame.page.next,
              limit: SyncEngine.defaultPageSize,
            ),
          );
        }
      case NotifyFrame():
        // Inline rows are an optimisation; ignoring them can never lose data
        // because the cursor pull is authoritative.
        await _pull();
      case AckFrame():
        await _sync.markAcked(peerId, frame.seq);
      case PingFrame():
        await _send(PongFrame(ts: frame.ts));
      case PongFrame():
        _lastPong = _nowMs();
      case ErrorFrame():
        _logger.warn(
          'ws: peer error frame',
          fields: {'peer': peerId, 'code': frame.code},
        );
      case UnknownFrame():
        // Forward compatible: ignore unknown types.
        break;
    }
  }

  Future<void> _servePull(PullFrame frame) async {
    final limit = frame.limit.clamp(1, 500);
    final after = frame.after < 0 ? 0 : frame.after;
    final page = await _sync.pullPage(
      requesterPeerId: peerId,
      after: after,
      limit: limit,
    );
    await _send(ChangesFrame(page));
    // `Sent` means written to the socket; the ack from the peer will make them
    // Delivered.
    await _sync.markSentFromPage(peerId, page);
  }

  Future<void> _pull() async {
    if (!_ready || _closed) return;
    if (_pulling) {
      _pullQueued = true;
      return;
    }
    _pulling = true;
    try {
      do {
        _pullQueued = false;
        final peer = await _peers.get(peerId);
        if (peer == null) {
          await _close(CloseCodes.unauthorized, CloseCodes.reasonUnauthorized);
          return;
        }
        await _send(
          PullFrame(after: peer.remoteSeq, limit: SyncEngine.defaultPageSize),
        );
      } while (_pullQueued && _ready && !_closed);
    } finally {
      _pulling = false;
    }
  }

  Future<void> _notifyPeer() async {
    if (!_ready || _closed) return;
    try {
      final seq = await _sync.localSeq();
      await _send(NotifyFrame(seq: seq));
    } on Object catch (e) {
      _logger.debug('ws: notify failed', fields: {'error': e.runtimeType});
    }
  }

  Future<void> _send(Frame frame) async {
    if (_closed) return;
    try {
      _sendRaw(FrameCodec.encode(frame));
    } on Object catch (e) {
      _logger.warn('ws: send failed', fields: {'error': e.runtimeType});
    }
  }

  Future<void> _close(int code, String reason) async {
    if (_closed) return;
    _closed = true;
    _handshakeTimer?.cancel();
    _pingTimer?.cancel();
    await _busSub?.cancel();
    _busSub = null;
    try {
      await _closeSocket(code, reason);
    } on Object {
      // Socket already gone.
    }
    _onEnded(this, code, reason);
  }

  /// Socket closed by the remote side or by the owner.
  Future<void> handleSocketClosed([int? code, String? reason]) async {
    if (_closed) return;
    _closed = true;
    _handshakeTimer?.cancel();
    _pingTimer?.cancel();
    await _busSub?.cancel();
    _busSub = null;
    _onEnded(this, code, reason);
  }

  /// Close the session and release everything.
  ///
  /// [code]/[reason] are sent to the peer, so a revoked device really receives
  /// 4403 (`docs/05` §Close codes, `docs/08` "Revocation closes live
  /// sockets"). They are ignored when the socket is already gone.
  Future<void> dispose({
    int code = CloseCodes.internal,
    String reason = CloseCodes.reasonInternal,
  }) async {
    if (_closed) return;
    _closed = true;
    _handshakeTimer?.cancel();
    _pingTimer?.cancel();
    await _busSub?.cancel();
    _busSub = null;
    try {
      await _closeSocket(code, reason);
    } on Object {
      // Socket already gone.
    }
    _onEnded(this, code, reason);
  }
}
