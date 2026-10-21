import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';
import 'package:twindrop_core/db/store_ops.dart';

import 'support/test_support.dart';

void main() {
  late AppDatabase db;
  late HlcClock clock;
  late MergeEngine merge;

  setUp(() {
    db = AppDatabase.memory();
    clock = HlcClock(deviceId: 'device-a', nowMs: () => 1000);
    merge = MergeEngine(db: db, clock: clock, logger: Logger.silent);
  });

  tearDown(() async {
    await db.close();
  });

  group('mergeItem - content group', () {
    test('inserts a remote item that does not exist locally', () async {
      final remote = makeItem(
        id: testUuid(1),
        text: 'from the peer',
        contentHlc: hlcValue(1000, 1, 'b'),
      );
      final result = await merge.mergeItem(remote, fromPeer: 'peer-b');
      expect(result.inserted, isTrue);
      expect(result.changed, isTrue);
      expect(result.item!.text, 'from the peer');
      expect(await db.itemById(remote.id), isNotNull);
    });

    test(
      'keeps the local content when both sides have the same hash',
      () async {
        final local = makeItem(
          id: testUuid(2),
          text: 'same',
          contentHlc: hlcValue(1000, 1, 'a'),
        );
        await db.putItem(local);
        final remote = makeItem(
          id: testUuid(2),
          text: 'same',
          contentHlc: hlcValue(5000, 1, 'b'),
        );
        final result = await merge.mergeItem(remote, fromPeer: 'peer-b');
        expect(result.conflictCopyCreated, isFalse);
        expect(result.item!.text, 'same');
      },
    );

    test('takes the remote content on a fast-forward', () async {
      final local = makeItem(
        id: testUuid(3),
        text: 'v1',
        contentHlc: hlcValue(1000, 1, 'a'),
      );
      await db.putItem(local);
      final remote = makeItem(
        id: testUuid(3),
        text: 'v2',
        prevHash: local.contentHash,
        contentHlc: hlcValue(2000, 1, 'b'),
      );
      final result = await merge.mergeItem(remote, fromPeer: 'peer-b');
      expect(
        result.conflictCopyCreated,
        isFalse,
        reason: 'a fast-forward is not a conflict',
      );
      expect(result.item!.text, 'v2');
      expect(result.item!.prevHash, local.contentHash);
    });

    test('keeps the local content when the remote row is stale', () async {
      final local = makeItem(
        id: testUuid(4),
        text: 'v2',
        prevHash: contentHashOf(text: 'v1', title: null, url: null),
        contentHlc: hlcValue(2000, 1, 'a'),
      );
      await db.putItem(local);
      final remote = makeItem(
        id: testUuid(4),
        text: 'v1',
        contentHlc: hlcValue(1000, 1, 'b'),
      );
      final result = await merge.mergeItem(remote, fromPeer: 'peer-b');
      expect(result.conflictCopyCreated, isFalse);
      expect(result.item!.text, 'v2');
    });
  });

  group('mergeItem - concurrent edit', () {
    test('produces a conflict copy instead of a silent overwrite', () async {
      const id = '018f0000-0000-7000-8000-00000000000a';
      final local = makeItem(
        id: id,
        text: 'local text',
        contentHlc: hlcValue(1000, 1, 'a'),
      );
      await db.putItem(local);

      final remote = makeItem(
        id: id,
        text: 'remote text',
        contentHlc: hlcValue(2000, 1, 'b'),
      );
      final result = await merge.mergeItem(remote, fromPeer: 'peer-b');

      expect(result.conflictCopyCreated, isTrue);
      expect(
        result.item!.text,
        'remote text',
        reason: 'the higher content HLC wins',
      );
      expect(result.item!.contentHlc, remote.contentHlc);

      final copy = await db.itemById(result.conflictCopy!.id);
      expect(copy, isNotNull);
      expect(
        copy!.text,
        'local text',
        reason: 'the losing content must not be lost',
      );
      expect(copy.isConflictCopy, isTrue);
      expect(copy.type, ItemType.note);
      expect(copy.title, 'Conflict copy: local text');
      expect(copy.id, conflictCopyIdFor(id, local.contentHash));
    });

    test('the conflict copy id is identical on both devices', () async {
      const id = '018f0000-0000-7000-8000-00000000000b';

      // Device A holds the older text, device B holds the newer text.
      final dbA = AppDatabase.memory();
      final dbB = AppDatabase.memory();
      addTearDown(() async {
        await dbA.close();
        await dbB.close();
      });
      final mergeA = MergeEngine(
        db: dbA,
        clock: HlcClock(deviceId: 'a', nowMs: () => 1000),
        logger: Logger.silent,
      );
      final mergeB = MergeEngine(
        db: dbB,
        clock: HlcClock(deviceId: 'b', nowMs: () => 1000),
        logger: Logger.silent,
      );

      final older = makeItem(
        id: id,
        text: 'older text',
        contentHlc: hlcValue(1000, 1, 'a'),
      );
      final newer = makeItem(
        id: id,
        text: 'newer text',
        contentHlc: hlcValue(2000, 1, 'b'),
      );
      await dbA.putItem(older);
      await dbB.putItem(newer);

      final resultA = await mergeA.mergeItem(newer, fromPeer: 'peer-b');
      final resultB = await mergeB.mergeItem(older, fromPeer: 'peer-a');

      expect(resultA.item!.text, 'newer text');
      expect(
        resultB.item!.text,
        'newer text',
        reason: 'both devices must converge on the same winner',
      );
      expect(resultA.conflictCopy!.id, resultB.conflictCopy!.id);
      expect(resultA.conflictCopy!.text, resultB.conflictCopy!.text);
      expect(
        resultA.conflictCopy!.id,
        conflictCopyIdFor(id, older.contentHash),
      );
    });

    test('does not create the conflict copy twice', () async {
      const id = '018f0000-0000-7000-8000-00000000000c';
      final local = makeItem(
        id: id,
        text: 'local text',
        contentHlc: hlcValue(1000, 1, 'a'),
      );
      await db.putItem(local);
      final remote = makeItem(
        id: id,
        text: 'remote text',
        contentHlc: hlcValue(2000, 1, 'b'),
      );

      final first = await merge.mergeItem(remote, fromPeer: 'peer-b');
      expect(first.conflictCopyCreated, isTrue);
      final second = await merge.mergeItem(remote, fromPeer: 'peer-b');
      expect(
        second.conflictCopyCreated,
        isFalse,
        reason: 'the content now matches, so there is no loser left',
      );
      expect(second.conflictCopy, isNull);
      // The copy created by the first merge is still there - exactly one.
      final copy = await db.itemById(first.conflictCopy!.id);
      expect(copy, isNotNull);
      expect(copy!.text, 'local text');

      final copies = await db.listItems(type: ItemType.note, limit: 100);
      expect(copies.where((c) => c.isConflictCopy).length, 1);
    });

    test('the conflict copy keeps the category of the merged item', () async {
      const id = '018f0000-0000-7000-8000-00000000000d';
      final local = makeItem(
        id: id,
        text: 'local text',
        categoryId: 'cat-1',
        contentHlc: hlcValue(1000, 1, 'a'),
      );
      await db.putItem(local);
      final remote = makeItem(
        id: id,
        text: 'remote text',
        categoryId: 'cat-1',
        contentHlc: hlcValue(2000, 1, 'b'),
      );
      final result = await merge.mergeItem(remote, fromPeer: 'peer-b');
      final copy = await db.itemById(result.conflictCopy!.id);
      expect(copy!.categoryId, 'cat-1');
    });
  });

  group('mergeItem - meta group', () {
    test('the newer meta HLC wins for pinned', () async {
      final local = makeItem(
        id: testUuid(5),
        text: 'note',
        pinned: false,
        contentHlc: hlcValue(1000, 1, 'a'),
        metaHlc: hlcValue(1000, 1, 'a'),
      );
      await db.putItem(local);
      final remote = makeItem(
        id: testUuid(5),
        text: 'note',
        pinned: true,
        contentHlc: hlcValue(1000, 1, 'a'),
        metaHlc: hlcValue(2000, 1, 'b'),
      );
      final result = await merge.mergeItem(remote, fromPeer: 'peer-b');
      expect(result.item!.pinned, isTrue);
      expect(result.item!.metaHlc, hlcValue(2000, 1, 'b'));
    });

    test('the older meta HLC loses for pinned', () async {
      final local = makeItem(
        id: testUuid(6),
        text: 'note',
        pinned: true,
        contentHlc: hlcValue(1000, 1, 'a'),
        metaHlc: hlcValue(2000, 1, 'a'),
      );
      await db.putItem(local);
      final remote = makeItem(
        id: testUuid(6),
        text: 'note',
        pinned: false,
        contentHlc: hlcValue(1000, 1, 'a'),
        metaHlc: hlcValue(1000, 1, 'b'),
      );
      final result = await merge.mergeItem(remote, fromPeer: 'peer-b');
      expect(result.item!.pinned, isTrue);
    });

    test('messages never get a category', () async {
      final local = makeItem(
        id: testUuid(7),
        type: ItemType.message,
        text: 'hello',
        contentHlc: hlcValue(1000, 1, 'a'),
      );
      await db.putItem(local);
      final remote = makeItem(
        id: testUuid(7),
        type: ItemType.message,
        text: 'hello',
        categoryId: 'cat-x',
        contentHlc: hlcValue(2000, 1, 'b'),
        metaHlc: hlcValue(2000, 1, 'b'),
      );
      final result = await merge.mergeItem(remote, fromPeer: 'peer-b');
      expect(result.item!.categoryId, isNull);
      expect(result.item!.type, ItemType.message);
    });
  });

  group('mergeItem - delete vs edit', () {
    test('a newer delete tombstone beats an older edit', () async {
      final local = makeItem(
        id: testUuid(8),
        text: 'note',
        contentHlc: hlcValue(1000, 1, 'a'),
        metaHlc: hlcValue(2000, 1, 'a'),
        deleted: true,
        deletedHlc: hlcValue(2000, 1, 'a'),
      );
      await db.putItem(local);
      // The peer still has the pre-delete version.
      final remote = makeItem(
        id: testUuid(8),
        text: 'note',
        contentHlc: hlcValue(1000, 1, 'b'),
        metaHlc: hlcValue(1000, 1, 'b'),
      );
      final result = await merge.mergeItem(remote, fromPeer: 'peer-b');
      expect(result.item!.deleted, isTrue, reason: 'the newer tombstone wins');
      expect(result.restored, isFalse);
    });

    test('an edit newer than the tombstone restores the item', () async {
      final local = makeItem(
        id: testUuid(9),
        text: 'v1',
        contentHlc: hlcValue(1000, 1, 'a'),
        metaHlc: hlcValue(2000, 1, 'a'),
        deleted: true,
        deletedHlc: hlcValue(2000, 1, 'a'),
      );
      await db.putItem(local);
      // The peer edited the content after the delete happened, but its meta
      // group is still the old one.
      final remote = makeItem(
        id: testUuid(9),
        text: 'v2',
        prevHash: local.contentHash,
        contentHlc: hlcValue(3000, 1, 'b'),
        metaHlc: hlcValue(1000, 1, 'b'),
      );
      final result = await merge.mergeItem(remote, fromPeer: 'peer-b');
      expect(
        result.restored,
        isTrue,
        reason: 'content is never lost to a concurrent delete',
      );
      expect(result.item!.deleted, isFalse);
      expect(result.item!.restored, isTrue);
      expect(result.item!.text, 'v2');
    });
  });

  group('mergeCategory', () {
    test('the newer meta HLC wins', () async {
      await db.putCategory(
        makeCategory(
          id: testUuid(20),
          name: 'Research',
          metaHlc: hlcValue(1000, 1, 'a'),
        ),
      );
      final result = await merge.mergeCategory(
        makeCategory(
          id: testUuid(20),
          name: 'Research Notes',
          metaHlc: hlcValue(2000, 1, 'b'),
        ),
        fromPeer: 'peer-b',
      );
      expect(result.changed, isTrue);
      expect(result.category!.name, 'Research Notes');
    });

    test('the older meta HLC loses', () async {
      await db.putCategory(
        makeCategory(
          id: testUuid(21),
          name: 'Research Notes',
          metaHlc: hlcValue(2000, 1, 'a'),
        ),
      );
      final result = await merge.mergeCategory(
        makeCategory(
          id: testUuid(21),
          name: 'Research',
          metaHlc: hlcValue(1000, 1, 'b'),
        ),
        fromPeer: 'peer-b',
      );
      expect(result.changed, isFalse);
      expect(result.category!.name, 'Research Notes');
    });

    test('the Inbox is never deleted by a merge', () async {
      await db.putCategory(
        makeCategory(
          id: Category.inboxId,
          name: 'Inbox',
          isInbox: true,
          metaHlc: hlcValue(1000, 1, 'a'),
        ),
      );
      final result = await merge.mergeCategory(
        makeCategory(
          id: Category.inboxId,
          name: 'Inbox',
          isInbox: true,
          metaHlc: hlcValue(5000, 1, 'b'),
          deleted: true,
        ),
        fromPeer: 'peer-b',
      );
      expect(result.category!.deleted, isFalse);
      expect(result.category!.name, 'Inbox');
      final stored = await db.categoryById(Category.inboxId);
      expect(stored!.deleted, isFalse);
    });

    test(
      'concurrently created categories with the same name collapse',
      () async {
        // Two devices created "Research" at the same time with different ids.
        const winnerId = '018f0000-0000-7000-8000-000000000001';
        const loserId = '018f0000-0000-7000-8000-000000000002';
        await db.putCategory(
          makeCategory(
            id: winnerId,
            name: 'Research',
            metaHlc: hlcValue(1000, 1, 'a'),
          ),
        );
        await db.putCategory(
          makeCategory(
            id: loserId,
            name: 'research',
            metaHlc: hlcValue(1000, 2, 'a'),
          ),
        );
        await db.putItem(
          makeItem(
            id: testUuid(30),
            text: 'note in the loser',
            categoryId: loserId,
            contentHlc: hlcValue(1000, 1, 'a'),
          ),
        );

        final result = await merge.mergeCategory(
          makeCategory(
            id: loserId,
            name: 'research',
            metaHlc: hlcValue(2000, 1, 'b'),
          ),
          fromPeer: 'peer-b',
        );
        expect(result.category, isNotNull);

        // The category with the smaller id survives.
        final winner = await db.categoryById(winnerId);
        final loser = await db.categoryById(loserId);
        expect(winner!.deleted, isFalse);
        expect(loser!.deleted, isTrue, reason: 'the loser is tombstoned');
        // The notes of the loser move to the winner.
        final moved = await db.itemById(testUuid(30));
        expect(moved!.categoryId, winnerId);
        expect(moved.deleted, isFalse);
      },
    );
  });

  group('merge helpers', () {
    test('maxHlcOfItem returns the highest HLC of the row', () {
      final item = makeItem(
        id: testUuid(40),
        text: 'note',
        contentHlc: hlcValue(1000, 1, 'a'),
        metaHlc: hlcValue(3000, 1, 'a'),
        deleted: true,
        deletedHlc: hlcValue(2000, 1, 'a'),
      );
      final max = MergeEngine.maxHlcOfItem(item);
      expect(max, isNotNull);
      expect(max!.wallMs, 3000);
    });

    test('maxHlcOfItem ignores malformed HLC values', () {
      final item = Item(
        id: testUuid(41),
        type: ItemType.note,
        kind: ItemKind.text,
        text: 'note',
        originDevice: 'a',
        originName: 'A',
        createdAt: 1,
        contentHash: contentHashOf(text: 'note', title: null, url: null),
        contentHlc: 'garbage',
        metaHlc: hlcValue(1000, 1, 'a'),
      );
      final max = MergeEngine.maxHlcOfItem(item);
      expect(max!.wallMs, 1000);
    });
  });
}
