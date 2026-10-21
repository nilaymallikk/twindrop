import 'dart:convert';
import 'dart:math';

import '../db/database.dart';
import '../db/store_ops.dart';
import '../models/category.dart';
import '../models/enums.dart';
import '../models/errors.dart';
import '../models/item.dart';
import '../models/peer.dart';
import '../util/hlc.dart';
import '../util/logger.dart';
import 'change_bus.dart';
import 'merge_engine.dart';
import 'remote_validation.dart';

/// One change-log entry plus the current row it points at.
class ChangeRecord {
  const ChangeRecord({
    required this.seq,
    required this.entityType,
    required this.entityId,
    this.row,
  });

  final int seq;
  final String entityType;
  final String entityId;

  /// Current row snapshot (item/category JSON). Null means the local row is
  /// missing, which the receiver treats as an unsupported/malformed change.
  final Map<String, dynamic>? row;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'seq': seq,
        'et': entityType,
        'id': entityId,
        if (row != null) 'row': row,
      };

  static ChangeRecord fromJson(Map<String, dynamic> j) {
    final seq = j['seq'];
    final et = j['et'];
    final id = j['id'];
    if (seq is! int || et is! String || id is! String) {
      throw const ProtocolError('malformed change entry');
    }
    final row = j['row'];
    if (row != null && row is! Map) {
      throw const ProtocolError('malformed change row');
    }
    return ChangeRecord(
      seq: seq,
      entityType: et,
      entityId: id,
      row: row == null ? null : Map<String, dynamic>.from(row as Map),
    );
  }
}

/// A page of the change log (`docs/05` `changes` frame).
class ChangePage {
  const ChangePage({
    required this.records,
    required this.next,
    required this.more,
  });

  final List<ChangeRecord> records;

  /// Cursor to send as `after` for the next page.
  final int next;
  final bool more;

  static const ChangePage empty =
      ChangePage(records: <ChangeRecord>[], next: 0, more: false);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'entries': [for (final r in records) r.toJson()],
        'next': next,
        'more': more,
      };

  static ChangePage fromJson(Map<String, dynamic> j) {
    final rawEntries = j['entries'];
    final next = j['next'];
    final more = j['more'];
    if (rawEntries is! List || next is! int || more is! bool) {
      throw const ProtocolError('malformed changes page');
    }
    final records = <ChangeRecord>[];
    for (final e in rawEntries) {
      if (e is! Map) throw const ProtocolError('malformed change entry');
      records.add(ChangeRecord.fromJson(Map<String, dynamic>.from(e)));
    }
    return ChangePage(records: records, next: next, more: more);
  }
}

/// Result of applying one page transactionally.
class ApplyResult {
  const ApplyResult({
    required this.applied,
    required this.quarantined,
    required this.remoteSeq,
    this.replayed = 0,
  });

  final int applied;
  final int quarantined;
  final int remoteSeq;

  /// Entries skipped because `applied_remote` already contained them
  /// (`SYNC-003` replay guard).
  final int replayed;
}

/// Cursor sync (`docs/04` §Cursor sync, `docs/05` §Session).
///
/// The change log is authoritative; the WebSocket `notify`/`ack` frames are
/// only an optimisation. Pull excludes entries the requester itself originated
/// (no echo), and a page is applied atomically: rows merged + own change-log
/// rows appended + `applied_remote` recorded, then `remote_seq` advanced.
/// Nothing is advanced before the page commits.
class SyncEngine {
  SyncEngine({
    required AppDatabase db,
    required MergeEngine merge,
    required HlcClock clock,
    required ChangeBus bus,
    required Logger logger,
  })  : _db = db,
        _merge = merge,
        _clock = clock,
        _bus = bus,
        _logger = logger;

  final AppDatabase _db;
  final MergeEngine _merge;
  final HlcClock _clock;
  final ChangeBus _bus;
  final Logger _logger;

  static const int defaultPageSize = 200;

  Future<int> localSeq() => _db.lastChangeSeq();

  /// Serve a page of our own change log to [requesterPeerId].
  Future<ChangePage> pullPage({
    required String requesterPeerId,
    required int after,
    int limit = defaultPageSize,
  }) async {
    final rows = await _db.changesAfter(
      after: after,
      limit: limit + 1,
      excludeSourcePeer: requesterPeerId,
    );
    final more = rows.length > limit;
    final pageRows = more ? rows.sublist(0, limit) : rows;
    final records = <ChangeRecord>[];
    for (final entry in pageRows) {
      Map<String, dynamic>? row;
      if (entry.entityType == 'item') {
        final item = await _db.itemById(entry.entityId);
        row = item?.toJson();
      } else if (entry.entityType == 'category') {
        final category = await _db.categoryById(entry.entityId);
        row = category?.toJson();
      }
      records.add(ChangeRecord(
        seq: entry.seq,
        entityType: entry.entityType,
        entityId: entry.entityId,
        row: row,
      ));
    }
    final next = pageRows.isEmpty ? after : pageRows.last.seq;
    return ChangePage(records: records, next: next, more: more);
  }

  /// Mark messages included in a served/written page as `sent` for [peerId].
  /// Called by the session after the frame is written to the socket.
  Future<void> markSentFromPage(String peerId, ChangePage page) async {
    final ids = <String>[];
    for (final record in page.records) {
      if (record.entityType != 'item') continue;
      final row = record.row;
      if (row == null) continue;
      if (row['type'] == ItemType.message.wire) ids.add(record.entityId);
    }
    if (ids.isEmpty) return;
    await _db.setDeliveryState(peerId, ids, DeliveryState.sent);
  }

  /// Apply a page from [fromPeerId] in one transaction.
  ///
  /// Throws [UnsupportedVersionError] for unknown entity types (stop sync, do
  /// not skip-and-advance). Individual invalid rows are quarantined and the
  /// page still advances.
  Future<ApplyResult> applyPage({
    required String fromPeerId,
    required ChangePage page,
  }) async {
    var applied = 0;
    var quarantined = 0;
    var replayed = 0;
    late int newRemoteSeq;
    try {
      await _db.transaction(() async {
        final peer = await _db.peerById(fromPeerId);
        if (peer == null) {
          throw NotFoundError('unknown peer');
        }
        for (final record in page.records) {
          if (await _db.hasAppliedRemote(fromPeerId, record.seq)) {
            replayed++;
            continue;
          }
          if (record.entityType != 'item' &&
              record.entityType != 'category') {
            throw UnsupportedVersionError(
                'unknown entity type ${record.entityType}');
          }
          final row = record.row;
          if (row == null) {
            await _quarantine(fromPeerId, record, QuarantineReason.malformed);
            await _db.markAppliedRemote(fromPeerId, record.seq);
            quarantined++;
            continue;
          }
          if (record.entityType == 'item') {
            Item item;
            try {
              item = Item.fromJson(row);
            } on Object {
              await _quarantine(
                  fromPeerId, record, QuarantineReason.malformed);
              await _db.markAppliedRemote(fromPeerId, record.seq);
              quarantined++;
              continue;
            }
            _observeItem(item);
            final reason = validateRemoteItem(item);
            if (reason != null) {
              await _quarantine(fromPeerId, record, reason);
              await _db.markAppliedRemote(fromPeerId, record.seq);
              quarantined++;
              continue;
            }
            await _merge.mergeItem(item, fromPeer: fromPeerId);
          } else {
            Category category;
            try {
              category = Category.fromJson(row);
            } on Object {
              await _quarantine(
                  fromPeerId, record, QuarantineReason.malformed);
              await _db.markAppliedRemote(fromPeerId, record.seq);
              quarantined++;
              continue;
            }
            _observeCategory(category);
            final reason = validateRemoteCategory(category);
            if (reason != null) {
              await _quarantine(fromPeerId, record, reason);
              await _db.markAppliedRemote(fromPeerId, record.seq);
              quarantined++;
              continue;
            }
            await _merge.mergeCategory(category, fromPeer: fromPeerId);
          }
          await _db.markAppliedRemote(fromPeerId, record.seq);
          applied++;
        }
        // Cursor advances inside the same transaction, after every row above.
        newRemoteSeq = max(peer.remoteSeq, page.next);
        await _db.putPeer(peer.copyWith(remoteSeq: newRemoteSeq));
      });
    } on UnsupportedVersionError {
      rethrow;
    } on TwinDropError {
      rethrow;
    } on Object catch (e) {
      throw StorageError('failed to apply change page', cause: e);
    }
    _bus.notify();
    _logger.debug('sync: applied page', fields: {
      'applied': applied,
      'quarantined': quarantined,
      'replayed': replayed,
      'remoteSeq': newRemoteSeq,
    });
    return ApplyResult(
      applied: applied,
      quarantined: quarantined,
      remoteSeq: newRemoteSeq,
      replayed: replayed,
    );
  }

  void _observeItem(Item item) {
    final max = MergeEngine.maxHlcOfItem(item);
    if (max != null) _clock.observeEvent(max);
  }

  void _observeCategory(Category category) {
    final h = Hlc.tryParse(category.metaHlc);
    if (h != null) _clock.observeEvent(h);
  }

  Future<void> _quarantine(
      String peerId, ChangeRecord record, QuarantineReason reason) async {
    await _db.quarantine(QuarantineEntry(
      id: 0,
      peerId: peerId,
      entityType: record.entityType,
      entityId: record.entityId,
      reason: reason.wire,
      payloadJson: jsonEncode(record.row ?? const <String, dynamic>{}),
      receivedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    _logger.warn('sync: quarantined change', fields: {
      'entity': record.entityType,
      'reason': reason.wire,
    });
  }

  /// Remove tombstones that are old enough and acknowledged by every
  /// non-revoked peer (`SYNC-004`). Returns the number of rows removed.
  Future<int> gcTombstones({
    Duration minAge = const Duration(days: 30),
    DateTime? now,
  }) async {
    final n = now ?? DateTime.now();
    final peers = await _db.peerRows(includeRevoked: false);
    final minAcked = peers.isEmpty
        ? 1 << 62
        : peers.map((p) => p.ackedSeq).reduce(min);
    final deletedItems = await _db.listItems(onlyDeleted: true, limit: 10000);
    var removed = 0;
    for (final item in deletedItems) {
      final deletedHlc = Hlc.tryParse(item.deletedHlc ?? '');
      if (deletedHlc == null) continue;
      final age = n.millisecondsSinceEpoch - deletedHlc.wallMs;
      if (age < minAge.inMilliseconds) continue;
      final tombstoneSeq = await _db.changeSeqForEntity('item', item.id);
      if (tombstoneSeq > minAcked) continue;
      await _db.deleteItemRow(item.id);
      await _db.ftsRemove(item.id);
      await _db.customStatement(
        "DELETE FROM change_log WHERE entityType = 'item' AND entityId = ?",
        [item.id],
      );
      await _db.customStatement(
          'DELETE FROM peer_delivery WHERE itemId = ?', [item.id]);
      removed++;
    }
    if (removed > 0) {
      _bus.notify();
      _logger.info('sync: tombstone GC', fields: {'removed': removed});
    }
    return removed;
  }

  /// Cursor invalid or DB restored: keep local data, reset the peer cursor and
  /// replay its full change log through the normal merge rules (`SYNC-009`).
  Future<void> resyncFrom(String peerId) async {
    final peer = await _db.peerById(peerId);
    if (peer == null) throw NotFoundError('unknown peer');
    await _db.transaction(() async {
      await _db.putPeer(peer.copyWith(remoteSeq: 0));
      await _db.clearAppliedRemote(peerId);
    });
    _logger.info('sync: resync requested', fields: {'peer': peerId});
  }

  /// Apply an ack from [peerId]: update the peer's acked seq and flip message
  /// delivery states to `delivered` (`MSG-006`).
  Future<void> markAcked(String peerId, int ackedSeq) async {
    final peer = await _db.peerById(peerId);
    if (peer == null) return;
    if (ackedSeq > peer.ackedSeq) {
      await _db.putPeer(peer.copyWith(ackedSeq: ackedSeq));
    }
    final changed = await _db.markDeliveredUpTo(peerId, ackedSeq);
    if (changed > 0) {
      _bus.notify();
      _logger.debug('sync: messages delivered', fields: {'count': changed});
    }
  }
}
