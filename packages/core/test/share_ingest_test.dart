import 'dart:convert';

import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';

import 'support/test_support.dart';

void main() {
  late AppDatabase db;
  late ChangeBus bus;
  late HlcClock clock;
  late PeerRegistry peers;
  late SettingsStore settings;
  late NotepadService notepad;
  late ChatService chat;
  late ShareIngest share;
  late DateTime now;

  setUp(() async {
    db = AppDatabase.memory();
    bus = ChangeBus();
    clock = HlcClock(deviceId: 'phone', nowMs: () => 1000);
    peers = PeerRegistry(db: db, bus: bus, logger: Logger.silent);
    settings = SettingsStore(db);
    notepad = NotepadService(
      db: db,
      clock: clock,
      bus: bus,
      logger: Logger.silent,
      deviceId: 'phone',
      deviceName: 'Phone',
      nowMs: () => 1000,
    );
    chat = ChatService(
      db: db,
      clock: clock,
      bus: bus,
      logger: Logger.silent,
      peers: peers,
      deviceId: 'phone',
      deviceName: 'Phone',
      nowMs: () => 1000,
    );
    now = DateTime.utc(2026, 1, 1, 12);
    share = ShareIngest(
      db: db,
      clock: clock,
      bus: bus,
      logger: Logger.silent,
      notepad: notepad,
      chat: chat,
      settings: settings,
      now: () => now,
    );
    await notepad.ensureInbox();
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  group('share ingest', () {
    test('stores a shared link as one Inbox note', () async {
      final result = await share.ingestText(
        text: 'look at https://example.com/page',
        sourceApp: 'com.android.chrome',
      );
      expect(result.outcome, ShareOutcome.savedToNotepad);
      expect(result.hasItem, isTrue);

      final notes = await notepad.listNotes(categoryId: Category.inboxId);
      expect(notes.length, 1);
      expect(notes.first.categoryId, Category.inboxId);
      expect(notes.first.url, 'https://example.com/page');
      expect(notes.first.kind, ItemKind.link);
      expect(notes.first.sourceApp, 'com.android.chrome');
      expect(notes.first.text, 'look at https://example.com/page');
    });

    test(
      'the same URL twice inside the window creates only one note',
      () async {
        final first = await share.ingestText(text: 'https://example.com/page');
        final second = await share.ingestText(text: 'https://example.com/page');
        expect(first.outcome, ShareOutcome.savedToNotepad);
        expect(second.outcome, ShareOutcome.duplicate);
        expect(second.deduplicated, isTrue);
        expect(second.item!.id, first.item!.id);

        final notes = await notepad.listNotes(categoryId: Category.inboxId);
        expect(notes.length, 1);
      },
    );

    test(
      'the same URL after the dedupe window creates a second note',
      () async {
        await share.ingestText(text: 'https://example.com/page');
        now = now.add(const Duration(seconds: 11));
        final second = await share.ingestText(text: 'https://example.com/page');
        expect(second.outcome, ShareOutcome.savedToNotepad);
        final notes = await notepad.listNotes(categoryId: Category.inboxId);
        expect(notes.length, 2);
      },
    );

    test('rejects an empty share', () async {
      await expectLater(
        share.ingestText(text: '   '),
        throwsA(isA<ValidationError>()),
      );
    });

    test('rejects an unsupported payload without crashing', () async {
      expect(
        () => share.rejectUnsupported(mimeType: 'image/png'),
        throwsA(isA<ValidationError>()),
      );
    });

    test('stores a non-web scheme as plain text, never as a link', () async {
      final result = await share.ingestText(text: 'javascript:alert(1)');
      expect(result.item!.url, isNull);
      expect(result.item!.kind, ItemKind.text);
      expect(result.item!.text, 'javascript:alert(1)');
    });

    test(
      'cleans the Instagram tracking parameter but keeps the text',
      () async {
        const text =
            'https://www.instagram.com/reel/ABC/?igsh=XYZ&utm_source=ig_web';
        final result = await share.ingestText(text: text);
        expect(
          result.item!.url,
          'https://www.instagram.com/reel/ABC/?utm_source=ig_web',
        );
        expect(
          result.item!.text,
          text,
          reason: 'the original text is never rewritten',
        );
      },
    );

    test('the ask action writes nothing', () async {
      final result = await share.ingestText(
        text: 'https://example.com/page',
        action: ShareDefaultAction.ask,
      );
      expect(result.outcome, ShareOutcome.needsChoice);
      expect(result.hasItem, isFalse);
      expect(await notepad.listNotes(categoryId: Category.inboxId), isEmpty);
    });

    test('the chat action stores a message instead of a note', () async {
      final result = await share.ingestText(
        text: 'https://example.com/page',
        action: ShareDefaultAction.chat,
      );
      expect(result.outcome, ShareOutcome.sentAsChat);
      expect(result.item!.isMessage, isTrue);
      expect(await notepad.listNotes(categoryId: Category.inboxId), isEmpty);
      expect((await chat.listMessages()).length, 1);
    });

    test('alsoSendAsChat creates a message for the shared note', () async {
      final result = await share.ingestText(text: 'https://example.com/page');
      final message = await share.alsoSendAsChat(result.item!);
      expect(message.isMessage, isTrue);
      expect(message.text, 'https://example.com/page');
    });

    test('changeCategory moves the note', () async {
      final category = await notepad.createCategory('Research');
      final result = await share.ingestText(text: 'https://example.com/page');
      final moved = await share.changeCategory(result.item!, category.id);
      expect(moved.categoryId, category.id);
    });

    test('undo removes the just-created note', () async {
      final result = await share.ingestText(text: 'https://example.com/page');
      await share.undo(result);
      expect(await notepad.listNotes(categoryId: Category.inboxId), isEmpty);
    });

    test('willSync reflects the paired peers', () async {
      expect(await share.willSync(), isFalse);
      await peers.addPairedPeer(makePeer(id: 'desktop-1'));
      expect(await share.willSync(), isTrue);
      await peers.revoke('desktop-1');
      expect(await share.willSync(), isFalse);
    });

    test('the dedupe key is the normalised URL', () {
      expect(
        ShareIngest.dedupeKeyFor('see https://example.com/page.'),
        'https://example.com/page',
      );
      expect(
        ShareIngest.dedupeKeyFor('no link here'),
        sha256Hex(utf8.encode('no link here')),
      );
    });
  });
}
