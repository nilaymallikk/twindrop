import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';
import 'package:twindrop_core/db/store_ops.dart';

void main() {
  late AppDatabase db;
  late ChangeBus bus;
  late HlcClock clock;
  late NotepadService notepad;

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
    await notepad.ensureInbox();
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  group('Inbox category', () {
    test('is created with the fixed id and name', () async {
      final inbox = await db.categoryById(Category.inboxId);
      expect(inbox, isNotNull);
      expect(inbox!.id, 'inbox');
      expect(inbox.name, 'Inbox');
      expect(inbox.isInbox, isTrue);
      expect(inbox.deleted, isFalse);
    });

    test('ensureInbox is idempotent', () async {
      final before = await db.categoryById(Category.inboxId);
      await notepad.ensureInbox();
      await notepad.ensureInbox();
      final after = await db.categoryById(Category.inboxId);
      expect(after!.id, before!.id);
      expect(after.name, 'Inbox');
      expect(after.deleted, isFalse);
    });

    test('cannot be renamed', () async {
      expect(
        () => notepad.renameCategory(Category.inboxId, 'Other'),
        throwsA(isA<ForbiddenError>()),
      );
      final inbox = await db.categoryById(Category.inboxId);
      expect(inbox!.name, 'Inbox');
    });

    test('cannot be deleted', () async {
      expect(
        () => notepad.deleteCategory(Category.inboxId),
        throwsA(isA<ForbiddenError>()),
      );
      final inbox = await db.categoryById(Category.inboxId);
      expect(inbox, isNotNull);
      expect(inbox!.deleted, isFalse);
    });

    test('the name "Inbox" is reserved for new categories', () async {
      expect(
        () => notepad.createCategory('Inbox'),
        throwsA(isA<ValidationError>()),
      );
      expect(
        () => notepad.createCategory('  inbox  '),
        throwsA(isA<ValidationError>()),
      );
    });

    test('a tombstoned Inbox row is repaired on the next start', () async {
      // Simulate a corrupted/tombstoned Inbox row and make sure the next
      // ensureInbox() brings it back: the Inbox must never disappear.
      await db.customStatement(
        "UPDATE categories SET deleted = 1 WHERE id = 'inbox'",
      );
      final broken = await db.categoryById(Category.inboxId);
      expect(broken!.deleted, isTrue);

      final repaired = await notepad.ensureInbox();
      expect(repaired.deleted, isFalse);
      expect(repaired.name, 'Inbox');
      expect(repaired.isInbox, isTrue);
    });
  });

  group('category name validation', () {
    // KNOWN DEVIATION: `models/errors.dart` states that every failure that
    // can cross a boundary - validation included - must be a typed
    // `TwinDropError`, but `validateCategoryName()` throws a raw
    // `FormatException`. The assertion below pins the current behaviour;
    // see the finding in the test report (validators.dart:166).
    test('rejects an empty name', () async {
      expect(
        () => notepad.createCategory(''),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a whitespace-only name', () async {
      expect(
        () => notepad.createCategory('    '),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => notepad.createCategory('\t\n '),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts a name of exactly 60 characters', () async {
      final category = await notepad.createCategory('a' * 60);
      expect(category.name.length, 60);
    });

    test('rejects a name of 61 characters', () async {
      expect(
        () => notepad.createCategory('a' * 61),
        throwsA(isA<FormatException>()),
      );
    });

    test('trims the stored name', () async {
      final category = await notepad.createCategory('  Research  ');
      expect(category.name, 'Research');
      expect(category.normalizedName, 'research');
    });
  });

  group('category duplicate detection', () {
    test('rejects an exact duplicate', () async {
      await notepad.createCategory('Research');
      expect(
        () => notepad.createCategory('Research'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('rejects a duplicate that differs only in case', () async {
      await notepad.createCategory('Research');
      expect(
        () => notepad.createCategory('research'),
        throwsA(isA<ValidationError>()),
      );
      expect(
        () => notepad.createCategory('RESEARCH'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('rejects a duplicate that differs only in whitespace', () async {
      await notepad.createCategory('Research Notes');
      expect(
        () => notepad.createCategory('  research   notes  '),
        throwsA(isA<ValidationError>()),
      );
    });

    test('allows the same name once the old category is deleted', () async {
      final first = await notepad.createCategory('Research');
      await notepad.deleteCategory(first.id);
      final second = await notepad.createCategory('research');
      expect(second.id, isNot(first.id));
    });

    test('rejects a rename onto an existing name', () async {
      await notepad.createCategory('Research');
      final other = await notepad.createCategory('Archive');
      expect(
        () => notepad.renameCategory(other.id, 'research'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('allows renaming a category to its own name', () async {
      final category = await notepad.createCategory('Research');
      final renamed = await notepad.renameCategory(category.id, 'Research');
      expect(renamed.name, 'Research');
    });
  });

  group('category deletion', () {
    test('moves the notes to the Inbox and tombstones the category', () async {
      final category = await notepad.createCategory('Research');
      final note = await notepad.createNote(
        text: 'a note',
        categoryId: category.id,
      );
      expect(note.categoryId, category.id);

      await notepad.deleteCategory(category.id);

      final tombstone = await db.categoryById(category.id);
      expect(tombstone!.deleted, isTrue);

      final moved = await notepad.getNote(note.id);
      expect(moved, isNotNull);
      expect(moved!.categoryId, Category.inboxId);
      expect(moved.text, 'a note', reason: 'content is never lost');
      expect(moved.deleted, isFalse);
    });

    test('the deleted category disappears from the live list', () async {
      final category = await notepad.createCategory('Research');
      await notepad.deleteCategory(category.id);
      final live = await notepad.listCategories();
      expect(live.any((c) => c.id == category.id), isFalse);
      final all = await notepad.listCategories(includeDeleted: true);
      expect(all.any((c) => c.id == category.id), isTrue);
    });
  });
}
