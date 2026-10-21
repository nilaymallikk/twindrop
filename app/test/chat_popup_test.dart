import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twindrop/features/chat/chat_popup.dart';
import 'package:twindrop/features/models.dart';
import 'package:twindrop/theme/theme.dart';
import 'package:twindrop_core/core.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: buildTdTheme(
      choice: AppThemeChoice.dark,
      platformBrightness: Brightness.dark,
    ),
    home: Scaffold(body: child),
  );
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
  group('desktop popup shortcuts (LNX-003)', () {
    testWidgets('Escape hides the popup', (tester) async {
      var closed = 0;
      await tester.pumpWidget(
        _host(
          ChatPopup(
            entries: const <ChatEntry>[],
            status: ConnectionStatus.connected,
            onOpenApp: () {},
            onSend: (_) {},
            onSaveToNotepad: (_) {},
            onClose: () => closed++,
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(closed, 1);
    });

    testWidgets('Ctrl+Shift+V sends the clipboard', (tester) async {
      var sent = 0;
      await tester.pumpWidget(
        _host(
          ChatPopup(
            entries: const <ChatEntry>[],
            status: ConnectionStatus.connected,
            onOpenApp: () {},
            onSend: (_) => sent++,
            onSaveToNotepad: (_) {},
            onSendClipboard: () => sent++,
          ),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(sent, 1);
    });

    testWidgets('Ctrl+S saves the newest message to the Notepad', (
      tester,
    ) async {
      final saved = <String>[];
      await tester.pumpWidget(
        _host(
          ChatPopup(
            entries: <ChatEntry>[_entry('m1', 'older'), _entry('m2', 'newest')],
            status: ConnectionStatus.connected,
            onOpenApp: () {},
            onSend: (_) {},
            onSaveToNotepad: (entry) => saved.add(entry.id),
          ),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(saved, <String>['m2']);
    });

    testWidgets('with no messages, Ctrl+S does nothing', (tester) async {
      final saved = <String>[];
      await tester.pumpWidget(
        _host(
          ChatPopup(
            entries: const <ChatEntry>[],
            status: ConnectionStatus.connected,
            onOpenApp: () {},
            onSend: (_) {},
            onSaveToNotepad: (entry) => saved.add(entry.id),
          ),
        ),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(saved, isEmpty);
    });
  });
}
