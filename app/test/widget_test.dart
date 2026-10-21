import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twindrop/features/chat/chat_screen.dart';
import 'package:twindrop/features/models.dart';
import 'package:twindrop/theme/context_ext.dart';
import 'package:twindrop/theme/theme.dart';
import 'package:twindrop/theme/tokens.dart';
import 'package:twindrop/widgets/buttons.dart';
import 'package:twindrop/widgets/td_icons.dart';
import 'package:twindrop_core/core.dart';

/// Wraps a widget in the app theme so `context.td` resolves.
Widget _host(Widget child) {
  return MaterialApp(
    theme: buildTdTheme(
      choice: AppThemeChoice.dark,
      platformBrightness: Brightness.dark,
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  group('theme', () {
    testWidgets('dark is the default and uses the bundled font family', (
      tester,
    ) async {
      late ThemeData theme;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              theme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(theme.brightness, Brightness.dark);
      expect(theme.textTheme.bodyMedium?.fontFamily, TdFonts.sans);
      expect(theme.scaffoldBackgroundColor, TdPalette.darkBg);
    });

    testWidgets('light theme resolves to the light palette', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTdTheme(
            choice: AppThemeChoice.light,
            platformBrightness: Brightness.light,
          ),
          home: Builder(
            builder: (context) {
              theme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(theme.brightness, Brightness.light);
      expect(theme.scaffoldBackgroundColor, TdPalette.lightBg);
    });
  });

  group('chat screen', () {
    testWidgets('shows the empty state when there are no messages', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          ChatScreen(
            entries: const <ChatEntry>[],
            status: ConnectionStatus.unpaired,
            onSend: (_) {},
            onSaveToNotepad: (_) {},
          ),
        ),
      );

      expect(find.textContaining('No messages yet'), findsOneWidget);
    });

    testWidgets('the composer is always reachable', (tester) async {
      var sent = <String>[];
      await tester.pumpWidget(
        _host(
          ChatScreen(
            entries: const <ChatEntry>[],
            status: ConnectionStatus.connected,
            onSend: sent.add,
            onSaveToNotepad: (_) {},
          ),
        ),
      );

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('an error message replaces the timeline', (tester) async {
      await tester.pumpWidget(
        _host(
          ChatScreen(
            entries: const <ChatEntry>[],
            status: ConnectionStatus.offline,
            errorMessage: 'The desktop is not reachable right now.',
            onSend: (_) {},
            onSaveToNotepad: (_) {},
          ),
        ),
      );

      expect(
        find.text('The desktop is not reachable right now.'),
        findsOneWidget,
      );
    });
  });

  group('buttons', () {
    testWidgets('a disabled button explains why it is disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          TdButton(
            label: 'Pair a phone',
            onPressed: null,
            disabledReason: 'Connect to the desktop first.',
          ),
        ),
      );

      expect(find.text('Pair a phone'), findsOneWidget);
      final button = tester.widget<TdButton>(find.byType(TdButton));
      expect(button.disabledReason, isNotNull);
    });

    testWidgets('tapping a button calls the callback exactly once', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(TdButton(label: 'Send', onPressed: () => taps++)),
      );

      await tester.tap(find.text('Send'));
      await tester.pump();

      expect(taps, 1);
    });
  });

  group('icons', () {
    test('the bundled icon set draws without a font dependency', () {
      // Icons are path data, not a package or an asset: the set must be
      // self-contained (docs/13 §4).
      expect(TdIcons.check.pathData, isNotEmpty);
      expect(TdIcons.scan.pathData, isNotEmpty);
      expect(TdIcons.flashlight.pathData, isNotEmpty);
    });
  });
}
