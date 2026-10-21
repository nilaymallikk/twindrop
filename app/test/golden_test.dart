import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twindrop/features/chat/chat_screen.dart';
import 'package:twindrop/features/models.dart';
import 'package:twindrop/features/notepad/notepad_screen.dart';
import 'package:twindrop/theme/theme.dart';
import 'package:twindrop_core/core.dart';

/// Golden tests for the two supported appearances (DES-001).
///
/// The golden files are regenerated with:
///   flutter test --update-goldens test/golden_test.dart
/// and are reviewed by eye against the anti-slop rules in `docs/13`.
///
/// `flutter_test` replaces every font with the Ahem test font, which draws
/// boxes. The real bundled IBM Plex faces are loaded here so the golden shows
/// the typography that actually ships (DES-003).
Future<void> _loadBundledFonts() async {
  Future<void> load(String family, String asset) async {
    final loader = FontLoader(family)
      ..addFont(rootBundle.load(asset));
    await loader.load();
  }

  await load('IBM Plex Sans', 'assets/fonts/IBMPlexSans-Regular.ttf');
  await load('IBM Plex Sans', 'assets/fonts/IBMPlexSans-Medium.ttf');
  await load('IBM Plex Sans', 'assets/fonts/IBMPlexSans-SemiBold.ttf');
  await load('IBM Plex Mono', 'assets/fonts/IBMPlexMono-Regular.ttf');
}

Future<void> _pumpAt(WidgetTester tester, Widget child, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTdTheme(
        choice: AppThemeChoice.dark,
        platformBrightness: Brightness.dark,
      ),
      home: Scaffold(body: child),
    ),
  );
  await tester.pumpAndSettle();
}

ChatEntry _entry(String id, String text) {
  return ChatEntry(
    item: Item(
      id: id,
      type: ItemType.message,
      kind: ItemKind.text,
      text: text,
      createdAt: 1700000000000,
      originDevice: '01a15d25-ebdb-7ce7-80a3-f05411833218',
      originName: 'Desk',
      contentHash: 'h$id',
      contentHlc: '001792564128739-00001-01a15d25-ebdb-7ce7',
      metaHlc: '001792564128739-00001-01a15d25-ebdb-7ce7',
    ),
    mine: true,
  );
}

void main() {
  const desktop = Size(900, 640);
  const phone = Size(360, 720);

  setUpAll(_loadBundledFonts);

  testWidgets('chat screen — dark, desktop width', (tester) async {
    await _pumpAt(
      tester,
      ChatScreen(
        entries: <ChatEntry>[
          _entry('m1', 'Shared a link from the phone.'),
          _entry('m2', 'And a reply from the desktop.'),
        ],
        status: ConnectionStatus.connected,
        peerName: 'Phone',
        onSend: (_) {},
        onSaveToNotepad: (_) {},
      ),
      desktop,
    );

    await expectLater(
      find.byType(ChatScreen),
      matchesGoldenFile('goldens/chat_dark_desktop.png'),
    );
  });

  testWidgets('chat screen — dark, phone width', (tester) async {
    await _pumpAt(
      tester,
      ChatScreen(
        entries: <ChatEntry>[_entry('m1', 'Shared a link from the phone.')],
        status: ConnectionStatus.connected,
        peerName: 'Phone',
        onSend: (_) {},
        onSaveToNotepad: (_) {},
      ),
      phone,
    );

    await expectLater(
      find.byType(ChatScreen),
      matchesGoldenFile('goldens/chat_dark_phone.png'),
    );
  });

  testWidgets('notepad — dark, desktop width', (tester) async {
    await _pumpAt(
      tester,
      NotepadScreen(
        categories: const <Category>[
          Category(
            id: 'inbox',
            name: 'Inbox',
            normalizedName: 'inbox',
            sortOrder: 0,
            isInbox: true,
            metaHlc: '001792564128739-00001-01a15d25-ebdb-7ce7',
          ),
        ],
        notes: const <Item>[],
        selectedCategoryId: 'inbox',
        categoryNames: const <String, String>{'inbox': 'Inbox'},
      ),
      desktop,
    );

    await expectLater(
      find.byType(NotepadScreen),
      matchesGoldenFile('goldens/notepad_dark_desktop.png'),
    );
  });
}
