import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';
import 'package:twindrop_core/db/store_ops.dart';

import 'support/test_support.dart';

void main() {
  late AppDatabase db;
  late ChangeBus bus;
  late HlcClock clock;
  late PeerRegistry peers;
  late NotepadService notepad;
  late ChatService chat;

  setUp(() async {
    db = AppDatabase.memory();
    bus = ChangeBus();
    clock = HlcClock(deviceId: 'device-a', nowMs: () => 1000);
    peers = PeerRegistry(db: db, bus: bus, logger: Logger.silent);
    notepad = NotepadService(
      db: db,
      clock: clock,
      bus: bus,
      logger: Logger.silent,
      deviceId: 'device-a',
      deviceName: 'Device A',
      nowMs: () => 1000,
    );
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
    await notepad.ensureInbox();
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  group('notes', () {
    test('every write appends a change-log row', () async {
      final before = await db.lastChangeSeq();
      final note = await notepad.createNote(text: 'a note');
      final after = await db.lastChangeSeq();
      expect(after, greaterThan(before));
      final rows = await db.changesAfter(after: before);
      expect(rows.first.entityId, note.id);
      expect(rows.first.entityType, 'item');
    });

    test('an edit keeps the hash chain', () async {
      final note = await notepad.createNote(text: 'v1');
      final edited = await notepad.updateNote(note.id, text: 'v2');
      expect(edited.text, 'v2');
      expect(edited.prevHash, note.contentHash);
      expect(edited.contentHash, isNot(note.contentHash));
    });

    test('pin, move and unpin update only the meta group', () async {
      final category = await notepad.createCategory('Research');
      final note = await notepad.createNote(text: 'a note');
      final pinned = await notepad.pinNote(note.id, true);
      expect(pinned.pinned, isTrue);
      expect(pinned.contentHash, note.contentHash,
          reason: 'pinning must not touch the content group');

      final moved = await notepad.moveNote(note.id, category.id);
      expect(moved.categoryId, category.id);
      expect(moved.contentHash, note.contentHash);

      final unpinned = await notepad.pinNote(note.id, false);
      expect(unpinned.pinned, isFalse);
    });

    test('moveNote rejects an unknown category', () async {
      final note = await notepad.createNote(text: 'a note');
      await expectLater(
        notepad.moveNote(note.id, 'does-not-exist'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('delete tombstones the note and restore brings it back', () async {
      final note = await notepad.createNote(text: 'a note');
      final deleted = await notepad.deleteNote(note.id);
      expect(deleted.deleted, isTrue);
      expect(deleted.deletedHlc, isNotNull);
      expect((await notepad.getNote(note.id))!.deleted, isTrue,
          reason: 'getNote returns the raw row, including the tombstone');
      expect(await notepad.listNotes(), isEmpty,
          reason: 'a deleted note is not in the visible list');

      final restored = await notepad.restoreNote(note.id);
      expect(restored.deleted, isFalse);
      expect(restored.text, 'a note');
      expect(await notepad.getNote(note.id), isNotNull);
    });

    test('recentlyDeleted lists the tombstones', () async {
      final note = await notepad.createNote(text: 'a note');
      await notepad.deleteNote(note.id);
      final recent = await notepad.recentlyDeleted();
      expect(recent.any((n) => n.id == note.id), isTrue);
    });

    test('search finds a note by its text', () async {
      await notepad.createNote(text: 'a very searchable note about otters');
      final hits = await notepad.search('otters');
      expect(hits.length, 1);
      expect(hits.first.text, contains('otters'));
    });

    test('search finds a note by its title', () async {
      await notepad.createNote(text: 'body', title: 'Distinctive Title');
      final hits = await notepad.search('Distinctive');
      expect(hits.length, 1);
    });

    test('search can be restricted to a category', () async {
      final category = await notepad.createCategory('Research');
      await notepad.createNote(text: 'shared word', categoryId: category.id);
      await notepad.createNote(text: 'shared word');

      final hits = await notepad.search('shared', categoryId: category.id);
      expect(hits.length, 1);
      expect(hits.first.categoryId, category.id);
    });

    test('search never returns a deleted note', () async {
      final note = await notepad.createNote(text: 'temporary keyword');
      await notepad.deleteNote(note.id);
      final hits = await notepad.search('temporary');
      expect(hits, isEmpty);
    });

    test('an empty search returns the notes of the category', () async {
      await notepad.createNote(text: 'a note');
      final hits = await notepad.search('   ');
      expect(hits.length, 1);
    });

    test('a malformed search query does not throw', () async {
      await notepad.createNote(text: 'a note');
      final hits = await notepad.search('"unbalanced');
      expect(hits, isNotNull);
    });

    test('conflict copies are listed separately', () async {
      final conflict = makeItem(
        id: testUuid(1),
        text: 'conflicting text',
        categoryId: Category.inboxId,
        contentHlc: hlcValue(2000, 1, 'b'),
        isConflictCopy: true,
      );
      await db.putItem(conflict);
      final copies = await notepad.listConflictCopies();
      expect(copies.length, 1);
      expect(copies.first.id, conflict.id);
    });
  });

  group('messages', () {
    test('a message is immutable: only the meta group can change', () async {
      final message = await chat.sendMessage('hello');
      final deleted = await chat.deleteMessage(message.id);
      expect(deleted.deleted, isTrue);
      expect(deleted.text, 'hello', reason: 'the content never changes');
      expect(deleted.contentHash, message.contentHash);
      expect(deleted.contentHlc, message.contentHlc);
    });

    test('deleting an unknown message fails', () async {
      await expectLater(
        chat.deleteMessage('nope'),
        throwsA(isA<NotFoundError>()),
      );
    });

    test('a message can be saved as a note', () async {
      final message = await chat.sendMessage('https://example.com/page');
      final note = await chat.saveMessageAsNote(message.id, noteTitle: 'Saved');
      expect(note.isNote, isTrue);
      expect(note.sourceItemId, message.id);
      expect(note.url, 'https://example.com/page');
      expect(note.title, 'Saved');
      expect(note.categoryId, Category.inboxId);
    });

    test('a message cannot be saved into an unknown category', () async {
      final message = await chat.sendMessage('hello');
      await expectLater(
        chat.saveMessageAsNote(message.id, categoryId: 'nope'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('messages are listed newest first', () async {
      await chat.sendMessage('first');
      await chat.sendMessage('second');
      final messages = await chat.listMessages();
      expect(messages.length, 2);
      expect(messages.first.text, 'second');
    });

    test('the change log records the message', () async {
      final before = await db.lastChangeSeq();
      final message = await chat.sendMessage('hello');
      final rows = await db.changesAfter(after: before);
      expect(rows.first.entityId, message.id);
    });
  });
}
