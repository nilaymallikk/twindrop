import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';
import 'package:twindrop_core/db/store_ops.dart';

import 'support/test_support.dart';

void main() {
  late AppDatabase db;
  late ChangeBus bus;
  late HlcClock clock;
  late MergeEngine merge;
  late SyncEngine sync;
  late PeerRegistry peers;

  const peerB = 'peer-b';

  setUp(() async {
    db = AppDatabase.memory();
    bus = ChangeBus();
    clock = HlcClock(deviceId: 'device-a', nowMs: () => 1000);
    merge = MergeEngine(db: db, clock: clock, logger: Logger.silent);
    sync = SyncEngine(
      db: db,
      merge: merge,
      clock: clock,
      bus: bus,
      logger: Logger.silent,
    );
    peers = PeerRegistry(db: db, bus: bus, logger: Logger.silent);
    await peers.addPairedPeer(makePeer(id: peerB));
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  group('change log', () {
    test('a local write appends a change row with no source peer', () async {
      await db.appendChange('item', testUuid(1));
      final rows = await db.changesAfter(after: 0);
      expect(rows.length, 1);
      expect(rows.first.sourcePeer, isNull);
      expect(rows.first.entityType, 'item');
    });

    test('pullPage never echoes the requester its own changes', () async {
      // A local change (source_peer = NULL) and a change we received from
      // peer B (source_peer = 'peer-b').
      await db.appendChange('item', 'local-item');
      await db.appendChange('item', 'from-peer-b', sourcePeer: peerB);

      final page = await sync.pullPage(requesterPeerId: peerB, after: 0);
      final ids = page.records.map((r) => r.entityId).toList();
      expect(ids, contains('local-item'));
      expect(ids, isNot(contains('from-peer-b')),
          reason: 'the requester must not receive its own changes back');
    });

    test('pullPage serves the rows with the current entity state', () async {
      final item = makeItem(
        id: testUuid(2),
        text: 'hello',
        contentHlc: hlcValue(1000, 1, 'a'),
      );
      await db.putItem(item);
      await db.appendChange('item', item.id);

      final page = await sync.pullPage(requesterPeerId: 'other', after: 0);
      expect(page.records.length, 1);
      expect(page.records.first.row, isNotNull);
      expect(page.records.first.row!['text'], 'hello');
      expect(page.next, page.records.first.seq);
    });

    test('pullPage honours the cursor', () async {
      await db.appendChange('item', 'a');
      await db.appendChange('item', 'b');
      final first = await sync.pullPage(requesterPeerId: 'other', after: 0);
      expect(first.records.length, 2);
      final second =
          await sync.pullPage(requesterPeerId: 'other', after: first.next);
      expect(second.records, isEmpty);
      expect(second.more, isFalse);
    });

    test('an applied remote change is appended to our own change log',
        () async {
      final remote = makeItem(
        id: testUuid(3),
        text: 'from peer',
        contentHlc: hlcValue(1000, 1, 'b'),
      );
      final result = await sync.applyPage(
        fromPeerId: peerB,
        page: ChangePage(
          records: [
            ChangeRecord(
              seq: 1,
              entityType: 'item',
              entityId: remote.id,
              row: remote.toJson(),
            ),
          ],
          next: 1,
          more: false,
        ),
      );
      expect(result.applied, 1);
      final rows = await db.changesAfter(after: 0);
      expect(rows.length, 1);
      expect(rows.first.sourcePeer, peerB,
          reason: 'the change must propagate to other peers');
    });
  });

  group('applyPage - cursor and atomicity', () {
    test('advances remote_seq after the page commits', () async {
      final remote = makeItem(
        id: testUuid(4),
        text: 'from peer',
        contentHlc: hlcValue(1000, 1, 'b'),
      );
      final result = await sync.applyPage(
        fromPeerId: peerB,
        page: ChangePage(
          records: [
            ChangeRecord(
              seq: 7,
              entityType: 'item',
              entityId: remote.id,
              row: remote.toJson(),
            ),
          ],
          next: 7,
          more: false,
        ),
      );
      expect(result.applied, 1);
      expect(result.remoteSeq, 7);
      final peer = await db.peerById(peerB);
      expect(peer!.remoteSeq, 7);
    });

    test('never advances remote_seq when the page fails', () async {
      final good = makeItem(
        id: testUuid(5),
        text: 'good',
        contentHlc: hlcValue(1000, 1, 'b'),
      );
      await expectLater(
        sync.applyPage(
          fromPeerId: peerB,
          page: ChangePage(
            records: [
              ChangeRecord(
                seq: 1,
                entityType: 'item',
                entityId: good.id,
                row: good.toJson(),
              ),
              // Unknown entity type: sync must stop, not skip.
              const ChangeRecord(
                seq: 2,
                entityType: 'alien',
                entityId: 'x',
              ),
            ],
            next: 2,
            more: false,
          ),
        ),
        throwsA(isA<UnsupportedVersionError>()),
      );

      final peer = await db.peerById(peerB);
      expect(peer!.remoteSeq, 0, reason: 'the cursor must not move');
      expect(await db.itemById(good.id), isNull,
          reason: 'the whole page must be rolled back');
      expect(await db.hasAppliedRemote(peerB, 1), isFalse);
    });

    test('stops the sync on an unknown entity type', () async {
      await expectLater(
        sync.applyPage(
          fromPeerId: peerB,
          page: ChangePage(
            records: const [
              ChangeRecord(seq: 1, entityType: 'alien', entityId: 'x'),
            ],
            next: 1,
            more: false,
          ),
        ),
        throwsA(isA<UnsupportedVersionError>()),
      );
    });

    test('refuses a page from an unknown peer', () async {
      await expectLater(
        sync.applyPage(
          fromPeerId: 'nobody',
          page: ChangePage.empty,
        ),
        throwsA(isA<NotFoundError>()),
      );
    });
  });

  group('applyPage - replay guard', () {
    test('replaying the same page changes nothing', () async {
      final remote = makeItem(
        id: testUuid(6),
        text: 'from peer',
        contentHlc: hlcValue(1000, 1, 'b'),
      );
      final page = ChangePage(
        records: [
          ChangeRecord(
            seq: 3,
            entityType: 'item',
            entityId: remote.id,
            row: remote.toJson(),
          ),
        ],
        next: 3,
        more: false,
      );

      final first = await sync.applyPage(fromPeerId: peerB, page: page);
      expect(first.applied, 1);
      expect(first.replayed, 0);

      final second = await sync.applyPage(fromPeerId: peerB, page: page);
      expect(second.applied, 0);
      expect(second.replayed, 1);

      // Exactly one row, no duplicate.
      final items = await db.listItems(type: ItemType.note, limit: 100);
      expect(items.length, 1);
      expect(items.first.id, remote.id);
    });

    test('resyncFrom resets the cursor and the replay guard', () async {
      final remote = makeItem(
        id: testUuid(7),
        text: 'from peer',
        contentHlc: hlcValue(1000, 1, 'b'),
      );
      final page = ChangePage(
        records: [
          ChangeRecord(
            seq: 3,
            entityType: 'item',
            entityId: remote.id,
            row: remote.toJson(),
          ),
        ],
        next: 3,
        more: false,
      );
      await sync.applyPage(fromPeerId: peerB, page: page);
      expect((await db.peerById(peerB))!.remoteSeq, 3);

      await sync.resyncFrom(peerB);
      expect((await db.peerById(peerB))!.remoteSeq, 0);
      expect(await db.hasAppliedRemote(peerB, 3), isFalse);

      // The very same page is applied again after the resync.
      final again = await sync.applyPage(fromPeerId: peerB, page: page);
      expect(again.applied, 1);
      expect(again.replayed, 0);
      final items = await db.listItems(type: ItemType.note, limit: 100);
      expect(items.length, 1, reason: 'the merge must not duplicate the row');
    });
  });

  group('applyPage - validation and quarantine', () {
    test('quarantines a row with an invalid URL scheme', () async {
      final hostile = makeItem(
        id: testUuid(8),
        text: 'click javascript:alert(1)',
        url: 'javascript:alert(1)',
        contentHlc: hlcValue(1000, 1, 'b'),
      );
      final result = await sync.applyPage(
        fromPeerId: peerB,
        page: ChangePage(
          records: [
            ChangeRecord(
              seq: 1,
              entityType: 'item',
              entityId: hostile.id,
              row: hostile.toJson(),
            ),
          ],
          next: 1,
          more: false,
        ),
      );
      expect(result.applied, 0);
      expect(result.quarantined, 1);
      expect(await db.itemById(hostile.id), isNull);

      final quarantined = await db.quarantined();
      expect(quarantined.length, 1);
      expect(quarantined.first.reason, QuarantineReason.invalidUrl.wire);
      expect(quarantined.first.peerId, peerB);
      expect(quarantined.first.entityId, hostile.id);
    });

    test('quarantines a malformed row but still advances the cursor',
        () async {
      final result = await sync.applyPage(
        fromPeerId: peerB,
        page: ChangePage(
          records: const [
            ChangeRecord(seq: 1, entityType: 'item', entityId: 'x'),
          ],
          next: 1,
          more: false,
        ),
      );
      expect(result.quarantined, 1);
      expect(result.remoteSeq, 1);
      expect((await db.peerById(peerB))!.remoteSeq, 1);
    });

    test('quarantines an oversize message', () async {
      final huge = makeItem(
        id: testUuid(9),
        type: ItemType.message,
        text: 'a' * (maxMessageBytes + 1),
        contentHlc: hlcValue(1000, 1, 'b'),
      );
      final result = await sync.applyPage(
        fromPeerId: peerB,
        page: ChangePage(
          records: [
            ChangeRecord(
              seq: 1,
              entityType: 'item',
              entityId: huge.id,
              row: huge.toJson(),
            ),
          ],
          next: 1,
          more: false,
        ),
      );
      expect(result.quarantined, 1);
      final quarantined = await db.quarantined();
      expect(quarantined.first.reason, QuarantineReason.oversize.wire);
    });

    test('quarantines a row whose id is not a UUID', () async {
      final bad = makeItem(
        id: 'not-a-uuid',
        text: 'x',
        contentHlc: hlcValue(1000, 1, 'b'),
      );
      final result = await sync.applyPage(
        fromPeerId: peerB,
        page: ChangePage(
          records: [
            ChangeRecord(
              seq: 1,
              entityType: 'item',
              entityId: bad.id,
              row: bad.toJson(),
            ),
          ],
          next: 1,
          more: false,
        ),
      );
      expect(result.quarantined, 1);
      expect((await db.quarantined()).first.reason,
          QuarantineReason.malformed.wire);
    });
  });

  group('delivery state machine', () {
    late ChatService chat;

    setUp(() {
      chat = ChatService(
        db: db,
        clock: clock,
        bus: bus,
        logger: Logger.silent,
        peers: peers,
        deviceId: 'device-a',
        deviceName: 'Device A',
        nowMs: () => 1000,
      );
    });

    test('a new message is queued for every paired peer', () async {
      final message = await chat.sendMessage('hello');
      final deliveries = await chat.deliveryFor(message.id);
      expect(deliveries.length, 1);
      expect(deliveries.first.peerId, peerB);
      expect(deliveries.first.state, DeliveryState.queued);
    });

    test('a message is only delivered after an ack', () async {
      final message = await chat.sendMessage('hello');

      // The page is written to the socket -> "sent".
      final page = await sync.pullPage(requesterPeerId: 'other', after: 0);
      await sync.markSentFromPage(peerB, page);
      var deliveries = await chat.deliveryFor(message.id);
      expect(deliveries.first.state, DeliveryState.sent);

      // No ack yet: still "sent", never "delivered".
      await sync.markAcked(peerB, 0);
      deliveries = await chat.deliveryFor(message.id);
      expect(deliveries.first.state, DeliveryState.sent);

      // The peer acknowledges our change seq.
      final seq = await db.changeSeqForEntity('item', message.id);
      await sync.markAcked(peerB, seq);
      deliveries = await chat.deliveryFor(message.id);
      expect(deliveries.first.state, DeliveryState.delivered);
    });

    test('an ack below the change seq does not deliver', () async {
      final message = await chat.sendMessage('hello');
      final seq = await db.changeSeqForEntity('item', message.id);
      await sync.markAcked(peerB, seq - 1);
      final deliveries = await chat.deliveryFor(message.id);
      expect(deliveries.first.state, DeliveryState.queued);
    });

    test('a message to a revoked peer is not queued', () async {
      await peers.revoke(peerB);
      final message = await chat.sendMessage('hello');
      final deliveries = await chat.deliveryFor(message.id);
      expect(deliveries, isEmpty);
    });
  });

  group('tombstone garbage collection', () {
    test('keeps a tombstone that is too young', () async {
      final item = makeItem(
        id: testUuid(10),
        text: 'gone',
        contentHlc: hlcValue(1000, 1, 'a'),
        metaHlc: hlcValue(1000, 1, 'a'),
        deleted: true,
        deletedHlc: hlcValue(1000, 1, 'a'),
      );
      await db.putItem(item);
      await db.appendChange('item', item.id);

      final removed = await sync.gcTombstones(
        minAge: const Duration(days: 30),
        now: DateTime.fromMillisecondsSinceEpoch(1000 + 1000),
      );
      expect(removed, 0);
      expect(await db.itemById(item.id), isNotNull);
    });

    test('removes an old tombstone once every peer acknowledged it', () async {
      final item = makeItem(
        id: testUuid(11),
        text: 'gone',
        contentHlc: hlcValue(1000, 1, 'a'),
        metaHlc: hlcValue(1000, 1, 'a'),
        deleted: true,
        deletedHlc: hlcValue(1000, 1, 'a'),
      );
      await db.putItem(item);
      final seq = await db.appendChange('item', item.id);
      await peers.updateRemoteSeq(peerB, 0);
      final peer = await db.peerById(peerB);
      await db.putPeer(peer!.copyWith(ackedSeq: seq));

      final removed = await sync.gcTombstones(
        minAge: const Duration(days: 30),
        now: DateTime.fromMillisecondsSinceEpoch(1000 + 31 * 24 * 3600 * 1000),
      );
      expect(removed, 1);
      expect(await db.itemById(item.id), isNull);
    });

    test('keeps an old tombstone that a peer did not acknowledge', () async {
      final item = makeItem(
        id: testUuid(12),
        text: 'gone',
        contentHlc: hlcValue(1000, 1, 'a'),
        metaHlc: hlcValue(1000, 1, 'a'),
        deleted: true,
        deletedHlc: hlcValue(1000, 1, 'a'),
      );
      await db.putItem(item);
      await db.appendChange('item', item.id);

      final removed = await sync.gcTombstones(
        minAge: const Duration(days: 30),
        now: DateTime.fromMillisecondsSinceEpoch(1000 + 31 * 24 * 3600 * 1000),
      );
      expect(removed, 0);
      expect(await db.itemById(item.id), isNotNull);
    });
  });
}
