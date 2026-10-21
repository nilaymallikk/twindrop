import 'dart:convert';

import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';
import 'package:twindrop_core/db/store_ops.dart';

import 'support/test_support.dart';

void main() {
  late AppDatabase db;
  late ChangeBus bus;
  late HlcClock clock;
  late NotepadService notepad;
  late ExportService export;

  setUp(() async {
    db = AppDatabase.memory();
    bus = ChangeBus();
    clock = HlcClock(deviceId: 'device-a', nowMs: () => 1000);
    notepad = NotepadService(
      db: db,
      clock: clock,
      bus: bus,
      logger: Logger.silent,
      deviceId: 'device-a',
      deviceName: 'Device A',
      nowMs: () => 1000,
    );
    export = ExportService(
      db: db,
      notepad: notepad,
      deviceName: 'Device A',
      now: () => DateTime.utc(2026, 1, 1, 12),
    );
    await notepad.ensureInbox();
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  group('markdown export', () {
    test('contains the categories and the notes', () async {
      await notepad.createNote(text: 'first note', title: 'First');
      final category = await notepad.createCategory('Research');
      await notepad.createNote(text: 'second note', categoryId: category.id);

      final document = await export.markdown();
      expect(document.mimeType, 'text/markdown');
      expect(document.fileName, endsWith('.md'));
      expect(document.fileName, startsWith('twindrop-notepad-'));
      expect(document.content, contains('# TwinDrop Notepad'));
      expect(document.content, contains('## Inbox'));
      expect(document.content, contains('## Research'));
      expect(document.content, contains('### First'));
      expect(document.content, contains('first note'));
      expect(document.content, contains('second note'));
      expect(document.content, contains('Exported 2026-01-01T12:00:00.000Z'));
    });

    test('marks a conflict copy and a pinned note', () async {
      final note = await notepad.createNote(text: 'a note', title: 'T');
      await notepad.pinNote(note.id, true);

      final conflict = makeItem(
        id: testUuid(1),
        text: 'conflicting text',
        title: 'Conflict copy: conflicting text',
        categoryId: Category.inboxId,
        contentHlc: hlcValue(2000, 1, 'b'),
        isConflictCopy: true,
      );
      await db.putItem(conflict);

      final document = await export.markdown();
      expect(document.content, contains('_Conflict copy_'));
      expect(document.content, contains('pinned'));
    });

    test('skips deleted notes', () async {
      final note = await notepad.createNote(text: 'doomed note');
      await notepad.deleteNote(note.id);
      final document = await export.markdown();
      expect(document.content, isNot(contains('doomed note')));
    });

    test('exports a single category when asked', () async {
      final category = await notepad.createCategory('Research');
      await notepad.createNote(text: 'in research', categoryId: category.id);
      await notepad.createNote(text: 'in inbox');

      final document = await export.markdown(categoryId: category.id);
      expect(document.content, contains('in research'));
      expect(document.content, isNot(contains('in inbox')));
    });

    test('renders a link note with its URL', () async {
      await notepad.createNote(text: 'see https://example.com/page');
      final document = await export.markdown();
      expect(document.content, contains('https://example.com/page'));
    });

    test('never contains a token or a pin', () async {
      await notepad.createNote(text: 'a note');
      final document = await export.markdown();
      expect(document.content.toLowerCase(), isNot(contains('bearer ')));
      expect(document.content, isNot(contains(DeviceTokens.issue())));
    });
  });

  group('json export', () {
    test('contains the categories and the notes as JSON', () async {
      await notepad.createNote(text: 'first note', title: 'First');
      final document = await export.json();
      expect(document.mimeType, 'application/json');
      expect(document.fileName, endsWith('.json'));

      final payload = jsonDecode(document.content) as Map<String, dynamic>;
      expect(payload['app'], 'twindrop');
      expect(payload['formatVersion'], 1);
      expect(payload['deviceName'], 'Device A');
      final categories = payload['categories'] as List<dynamic>;
      expect(
        categories.any((c) => (c as Map)['id'] == Category.inboxId),
        isTrue,
      );
      final notes = payload['notes'] as List<dynamic>;
      expect(notes.length, 1);
      expect((notes.first as Map)['text'], 'first note');
      expect((notes.first as Map)['title'], 'First');
      expect((notes.first as Map)['type'], 'note');
    });

    test('flags a conflict copy in the JSON export', () async {
      final conflict = makeItem(
        id: testUuid(2),
        text: 'conflicting text',
        categoryId: Category.inboxId,
        contentHlc: hlcValue(2000, 1, 'b'),
        isConflictCopy: true,
      );
      await db.putItem(conflict);
      final document = await export.json();
      final payload = jsonDecode(document.content) as Map<String, dynamic>;
      final notes = payload['notes'] as List<dynamic>;
      expect((notes.first as Map)['isConflictCopy'], isTrue);
    });
  });
}
