import 'package:drift/drift.dart';

import '../models/category.dart';
import '../models/change.dart';
import '../models/enums.dart';
import '../models/item.dart';
import '../models/peer.dart';
import '../sync/change_bus.dart';
import 'database.dart';
import 'mappers.dart';

/// Row-level database operations shared by the services, the merge engine and
/// the sync engine.
///
/// All methods are plain calls on [AppDatabase]; inside a `db.transaction(...)`
/// drift's zone redirects them to the transaction executor automatically, so
/// callers can compose them into one atomic write without passing an executor
/// around. Never call these from a different isolate.
extension StoreOps on AppDatabase {
  // ---------------------------------------------------------------- items ---

  Future<Item?> itemById(String id) async {
    final row = await (select(
      items,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row?.toDomain();
  }

  Future<void> putItem(Item item) async {
    await into(items).insertOnConflictUpdate(_itemCompanion(item));
  }

  Future<void> putItemIfAbsent(Item item) async {
    await into(items)
        .insert(_itemCompanion(item), mode: InsertMode.insertOrIgnore);
  }

  /// Items ordered newest-first. Messages use [type] = [ItemType.message] and
  /// [categoryId] stays null; notes filter by category.
  Future<List<Item>> listItems({
    ItemType? type,
    String? categoryId,
    bool includeDeleted = false,
    bool onlyDeleted = false,
    int limit = 200,
    int? beforeCreatedAt,
    String? beforeId,
  }) async {
    final q = select(items);
    if (type != null) q.where((t) => t.type.equals(type.wire));
    if (categoryId != null) {
      q.where((t) => t.categoryId.equals(categoryId));
    }
    if (!includeDeleted && !onlyDeleted) {
      q.where((t) => t.deleted.equals(false));
    } else if (onlyDeleted) {
      q.where((t) => t.deleted.equals(true));
    }
    if (beforeCreatedAt != null) {
      if (beforeId != null) {
        q.where(
          (t) =>
              t.createdAt.isSmallerThanValue(beforeCreatedAt) |
              (t.createdAt.equals(beforeCreatedAt) &
                  t.id.isSmallerThanValue(beforeId)),
        );
      } else {
        q.where((t) => t.createdAt.isSmallerThanValue(beforeCreatedAt));
      }
    }
    q
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
        (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
      ])
      ..limit(limit);
    final rows = await q.get();
    return rows.map((r) => r.toDomain()).toList(growable: false);
  }

  /// All live item ids in a category (used by category deletion/reassignment).
  Future<List<String>> itemIdsInCategory(String categoryId) async {
    final rows =
        await (select(items)..where(
              (t) => t.categoryId.equals(categoryId) & t.deleted.equals(false),
            ))
            .get();
    return rows.map((r) => r.id).toList(growable: false);
  }

  Future<void> deleteItemRow(String id) async {
    await (delete(items)..where((t) => t.id.equals(id))).go();
  }

  // ----------------------------------------------------------- categories ---

  Future<Category?> categoryById(String id) async {
    final row = await (select(
      categories,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row?.toDomain();
  }

  Future<void> putCategory(Category category) async {
    final inbox = category.id == Category.inboxId;
    await into(categories).insertOnConflictUpdate(
      CategoriesCompanion.insert(
        id: category.id,
        name: category.name,
        normalizedName: category.normalizedName,
        color: Value(category.color),
        sortOrder: Value(category.sortOrder),
        isInbox: Value(inbox || category.isInbox),
        metaHlc: category.metaHlc,
        // Inbox is never deleted (`docs/04` rule 7).
        deleted: Value(inbox ? false : category.deleted),
      ),
    );
  }

  Future<List<Category>> listCategoryRows({bool includeDeleted = false}) async {
    final q = select(categories);
    if (!includeDeleted) q.where((t) => t.deleted.equals(false));
    q.orderBy([
      (t) => OrderingTerm(expression: t.sortOrder),
      (t) => OrderingTerm(expression: t.name),
    ]);
    final rows = await q.get();
    return rows.map((r) => r.toDomain()).toList(growable: false);
  }

  /// Live categories group by normalized name, for collision reconciliation.
  Future<Map<String, List<Category>>> liveCategoriesByName() async {
    final rows = await listCategoryRows();
    final out = <String, List<Category>>{};
    for (final c in rows) {
      out.putIfAbsent(c.normalizedName, () => <Category>[]).add(c);
    }
    return out;
  }

  // ------------------------------------------------------------ change log ---

  /// Append one change-log row and return its seq. [sourcePeer] is null for a
  /// local origin (`docs/04` §Cursor sync).
  Future<int> appendChange(
    String entityType,
    String entityId, {
    String? sourcePeer,
    int? createdAt,
  }) async {
    return into(changeLogs).insert(
      ChangeLogsCompanion.insert(
        entityType: entityType,
        entityId: entityId,
        sourcePeer: Value(sourcePeer),
        createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  Future<List<ChangeEntry>> changesAfter({
    required int after,
    int limit = 200,
    String? excludeSourcePeer,
  }) async {
    final q = select(changeLogs)..where((t) => t.seq.isBiggerThanValue(after));
    if (excludeSourcePeer != null) {
      q.where(
        (t) =>
            t.sourcePeer.isNull() |
            t.sourcePeer.equals(excludeSourcePeer).not(),
      );
    }
    q
      ..orderBy([(t) => OrderingTerm(expression: t.seq)])
      ..limit(limit);
    final rows = await q.get();
    return rows.map((r) => r.toDomain()).toList(growable: false);
  }

  Future<int> changeSeqForEntity(String entityType, String entityId) async {
    final row = await customSelect(
      'SELECT COALESCE(MAX(seq), 0) AS m FROM change_log '
      'WHERE entity_type = ? AND entity_id = ?',
      variables: [Variable(entityType), Variable(entityId)],
      readsFrom: {changeLogs},
    ).getSingle();
    return row.read<int>('m');
  }

  /// Highest change seq <= [upToSeq] that concerns [itemId].
  Future<int> changeSeqForItemAtMost(String itemId, int upToSeq) async {
    final row = await customSelect(
      'SELECT COALESCE(MAX(seq), 0) AS m FROM change_log '
      "WHERE entity_type = 'item' AND entity_id = ? AND seq <= ?",
      variables: [Variable(itemId), Variable(upToSeq)],
      readsFrom: {changeLogs},
    ).getSingle();
    return row.read<int>('m');
  }

  // ---------------------------------------------------------- applied_remote ---

  Future<bool> hasAppliedRemote(String peerId, int peerSeq) async {
    final row =
        await (select(appliedRemotes)..where(
              (t) => t.peerId.equals(peerId) & t.peerSeq.equals(peerSeq),
            ))
            .getSingleOrNull();
    return row != null;
  }

  Future<void> markAppliedRemote(String peerId, int peerSeq) async {
    await into(appliedRemotes).insert(
      AppliedRemotesCompanion.insert(peerId: peerId, peerSeq: peerSeq),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> clearAppliedRemote(String peerId) async {
    await (delete(appliedRemotes)..where((t) => t.peerId.equals(peerId))).go();
  }

  // ---------------------------------------------------------- peer delivery ---

  Future<void> createQueuedDelivery(String peerId, String itemId) async {
    await into(peerDeliveries).insert(
      PeerDeliveriesCompanion.insert(
        peerId: peerId,
        itemId: itemId,
        state: const Value('queued'),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> setDeliveryState(
    String peerId,
    Iterable<String> itemIds,
    DeliveryState state,
  ) async {
    for (final id in itemIds) {
      await (update(peerDeliveries)
            ..where((t) => t.peerId.equals(peerId) & t.itemId.equals(id)))
          .write(PeerDeliveriesCompanion(state: Value(state.wire)));
    }
  }

  /// Marks all queued/sent deliveries up to [ackedSeq] as delivered. Only the
  /// peer's ack can do this (`MSG-006`).
  Future<int> markDeliveredUpTo(String peerId, int ackedSeq) async {
    final rows = await customSelect(
      "SELECT item_id FROM peer_delivery WHERE peer_id = ? AND state != 'delivered'",
      variables: [Variable(peerId)],
      readsFrom: {peerDeliveries},
    ).get();
    var changed = 0;
    for (final r in rows) {
      final itemId = r.read<String>('item_id');
      final seq = await changeSeqForItemAtMost(itemId, ackedSeq);
      if (seq == 0) continue;
      await (update(peerDeliveries)
            ..where((t) => t.peerId.equals(peerId) & t.itemId.equals(itemId)))
          .write(const PeerDeliveriesCompanion(state: Value('delivered')));
      changed++;
    }
    return changed;
  }

  Future<List<DeliveryInfo>> deliveriesForItem(String itemId) async {
    final rows = await (select(
      peerDeliveries,
    )..where((t) => t.itemId.equals(itemId))).get();
    return rows.map((r) => r.toDomain()).toList(growable: false);
  }

  Future<List<DeliveryInfo>> deliveriesForPeer(String peerId) async {
    final rows = await (select(
      peerDeliveries,
    )..where((t) => t.peerId.equals(peerId))).get();
    return rows.map((r) => r.toDomain()).toList(growable: false);
  }

  Future<int> queuedDeliveryCount() async {
    final row = await customSelect(
      "SELECT COUNT(*) AS c FROM peer_delivery WHERE state = 'queued'",
      readsFrom: {peerDeliveries},
    ).getSingle();
    return row.read<int>('c');
  }

  // ------------------------------------------------------------- quarantine ---

  Future<int> quarantine(QuarantineEntry entry) async {
    return into(quarantines).insert(
      QuarantinesCompanion.insert(
        peerId: entry.peerId,
        entityType: entry.entityType,
        entityId: entry.entityId,
        reason: entry.reason,
        payloadJson: entry.payloadJson,
        receivedAt: entry.receivedAt,
      ),
    );
  }

  Future<List<QuarantineEntry>> quarantined() async {
    final rows =
        await (select(quarantines)..orderBy([
              (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
            ]))
            .get();
    return rows.map((r) => r.toDomain()).toList(growable: false);
  }

  Future<int> quarantineCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM quarantine',
      readsFrom: {quarantines},
    ).getSingle();
    return row.read<int>('c');
  }

  Future<void> clearQuarantine() async {
    await delete(quarantines).go();
  }

  // ---------------------------------------------------------------- peers ---

  Future<Peer?> peerById(String id) async {
    final row = await (select(
      peers,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row?.toDomain();
  }

  Future<List<Peer>> peerRows({bool includeRevoked = true}) async {
    final q = select(peers);
    if (!includeRevoked) q.where((t) => t.revokedAt.isNull());
    q.orderBy([(t) => OrderingTerm(expression: t.createdAt)]);
    final rows = await q.get();
    return rows.map((r) => r.toDomain()).toList(growable: false);
  }

  Future<Peer?> peerByTokenHash(String tokenHash) async {
    final row = await (select(
      peers,
    )..where((t) => t.tokenHash.equals(tokenHash))).getSingleOrNull();
    return row?.toDomain();
  }

  Future<void> putPeer(Peer peer) async {
    await into(peers).insertOnConflictUpdate(
      PeersCompanion.insert(
        id: peer.id,
        name: peer.name,
        kind: peer.kind.wire,
        roleOfPeer: peer.roleOfPeer.wire,
        tokenHash: Value(peer.tokenHash),
        tokenRef: Value(peer.tokenRef),
        certFp: Value(peer.certFp),
        lastHost: Value(peer.lastHost),
        lastPort: Value(peer.lastPort),
        lastSeen: Value(peer.lastSeen),
        remoteSeq: Value(peer.remoteSeq),
        ackedSeq: Value(peer.ackedSeq),
        protocolVersion: Value(peer.protocolVersion),
        revokedAt: Value(peer.revokedAt),
        createdAt: peer.createdAt,
      ),
    );
  }

  Future<void> deletePeerRow(String id) async {
    await (delete(peers)..where((t) => t.id.equals(id))).go();
    await (delete(appliedRemotes)..where((t) => t.peerId.equals(id))).go();
    await (delete(peerDeliveries)..where((t) => t.peerId.equals(id))).go();
  }

  Future<void> touchPeerSeen(
    String id,
    int seenAt, {
    String? host,
    int? port,
  }) async {
    final peer = await peerById(id);
    if (peer == null) return;
    await putPeer(
      peer.copyWith(lastSeen: seenAt, lastHost: host, lastPort: port),
    );
  }

  // --------------------------------------------------------------- settings ---

  Future<String?> lastHlcValue() => getSetting('hlc.last');

  Future<void> saveHlcValue(String value) => setSetting('hlc.last', value);
}

Insertable<ItemRow> _itemCompanion(Item i) => ItemsCompanion.insert(
  id: i.id,
  type: i.type.wire,
  kind: i.kind.wire,
  textBody: i.text,
  title: Value(i.title),
  url: Value(i.url),
  sourceApp: Value(i.sourceApp),
  categoryId: Value(i.categoryId),
  originDevice: i.originDevice,
  originName: i.originName,
  sourceItemId: Value(i.sourceItemId),
  createdAt: i.createdAt,
  contentHash: i.contentHash,
  prevHash: Value(i.prevHash),
  contentHlc: i.contentHlc,
  pinned: Value(i.pinned),
  deleted: Value(i.deleted),
  deletedHlc: Value(i.deletedHlc),
  metaHlc: i.metaHlc,
  restored: Value(i.restored),
  isConflictCopy: Value(i.isConflictCopy),
);

/// Convenience used by services: notify the UI bus after a commit.
extension BusOps on ChangeBus {
  void notifyAfterCommit() => notify();
}
