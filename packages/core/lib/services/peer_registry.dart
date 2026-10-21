import 'dart:async';

import '../db/database.dart';
import '../db/store_ops.dart';
import '../models/peer.dart';
import '../util/logger.dart';
import '../sync/change_bus.dart';

/// Owns the `peers` table: paired devices, their pins, cursors and revocation
/// state (`docs/04`).
class PeerRegistry {
  PeerRegistry({
    required AppDatabase db,
    required ChangeBus bus,
    required Logger logger,
  })  : _db = db,
        _bus = bus,
        _logger = logger;

  final AppDatabase _db;
  final ChangeBus _bus;
  final Logger _logger;

  final StreamController<String> _revoked = StreamController<String>.broadcast();

  /// Emits peer ids as they are revoked, so live sockets can be closed with
  /// code 4403 (`docs/05` §Close codes).
  Stream<String> get revokedStream => _revoked.stream;

  Future<Peer?> get(String id) => _db.peerById(id);

  Future<List<Peer>> list({bool includeRevoked = true}) =>
      _db.peerRows(includeRevoked: includeRevoked);

  /// Non-revoked peers only (message fan-out, auth allow-list).
  Future<List<Peer>> active() => _db.peerRows(includeRevoked: false);

  Future<Peer?> findByTokenHash(String tokenHash) =>
      _db.peerByTokenHash(tokenHash);

  Future<Peer> upsert(Peer peer) async {
    await _db.putPeer(peer);
    _bus.notify();
    return peer;
  }

  Future<void> updateRemoteSeq(String peerId, int remoteSeq) async {
    final peer = await _db.peerById(peerId);
    if (peer == null || remoteSeq <= peer.remoteSeq) return;
    await _db.putPeer(peer.copyWith(remoteSeq: remoteSeq));
  }

  Future<void> touch(String peerId, {String? host, int? port, int? at}) async {
    await _db.touchPeerSeen(peerId, at ?? DateTime.now().millisecondsSinceEpoch,
        host: host, port: port);
  }

  /// Desktop-side revoke (`PAIR-009`): keeps the row for the history/diagnostics
  /// screen but rejects every future token and closes live sockets.
  Future<Peer?> revoke(String peerId) async {
    final peer = await _db.peerById(peerId);
    if (peer == null) return null;
    final updated = peer.copyWith(
      revokedAt: DateTime.now().millisecondsSinceEpoch,
      tokenHash: null,
    );
    await _db.putPeer(updated);
    _bus.notify();
    _logger.info('peer revoked', fields: {'peer': peerId});
    if (!_revoked.isClosed) _revoked.add(peerId);
    return updated;
  }

  /// Unpair/remove: deletes the row and its local bookkeeping. Used for the
  /// phone side ("removed") and for re-pair cleanup.
  Future<void> remove(String peerId) async {
    await _db.deletePeerRow(peerId);
    _bus.notify();
    if (!_revoked.isClosed) _revoked.add(peerId);
  }

  /// Pairing output: add the new peer with its pin (and token hash on the
  /// desktop / token ref on the phone).
  Future<Peer> addPairedPeer(Peer peer) async {
    await _db.putPeer(peer);
    _bus.notify();
    _logger.info('peer paired', fields: {'peer': peer.id, 'kind': peer.kind.wire});
    return peer;
  }

  Stream<List<Peer>> watch() async* {
    yield await list();
    await for (final _ in _bus.stream) {
      yield await list();
    }
  }

  Future<void> dispose() => _revoked.close();
}
