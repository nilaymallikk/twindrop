import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twindrop/features/chat/chat_screen.dart';
import 'package:twindrop/features/models.dart';
import 'package:twindrop/features/shell/app_shell.dart';
import 'package:twindrop/theme/theme.dart';
import 'package:twindrop/theme/tokens.dart';
import 'package:twindrop/theme/typography.dart';
import 'package:twindrop_core/models/enums.dart';
import 'package:twindrop_core/core.dart';

/// Regression tests for the "everything is underlined in yellow" bug.
///
/// A `Text` that is not below a `Material` inherits Flutter's fallback
/// `DefaultTextStyle`, which is yellow and double-underlined
/// ("consider putting your text in a Material"). The app renders its screens
/// without a `Scaffold` in some places, so the type scale has to be immune to
/// it, and the shell has to provide a `Material`.
void main() {
  group('type scale', () {
    test('no style inherits a decoration', () {
      final tokens = TdTokens.resolve(AppThemeChoice.dark, Brightness.dark);
      final type = TdType.fromTokens(tokens);
      for (final style in <TextStyle>[
        type.meta,
        type.secondary,
        type.body,
        type.bodyPhone,
        type.title,
        type.cardTitle,
        type.screen,
        type.label,
        type.code,
        type.mono,
      ]) {
        expect(
          style.decoration,
          anyOf(isNull, TextDecoration.none),
          reason: 'a style must not inherit an underline',
        );
      }
    });

    testWidgets('the theme text styles carry no underline', (tester) async {
      late ThemeData theme;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTdTheme(
            choice: AppThemeChoice.dark,
            platformBrightness: Brightness.dark,
          ),
          home: Builder(
            builder: (context) {
              theme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      for (final style
          in theme.textTheme.toString().isEmpty
              ? <TextStyle>[]
              : <TextStyle>[
                  theme.textTheme.bodyMedium!,
                  theme.textTheme.labelLarge!,
                  theme.textTheme.titleLarge!,
                ]) {
        expect(style.decoration, anyOf(isNull, TextDecoration.none));
      }
    });
  });

  group('app shell', () {
    testWidgets('text below the shell is not underlined', (tester) async {
      // Deliberately no Scaffold: this is how the app renders it.
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTdTheme(
            choice: AppThemeChoice.dark,
            platformBrightness: Brightness.dark,
          ),
          home: AppShell(
            section: AppSection.chat,
            onSectionChanged: (_) {},
            status: ConnectionStatus.connected,
            child: ChatScreen(
              entries: const <ChatEntry>[],
              status: ConnectionStatus.connected,
              onSend: (_) {},
              onSaveToNotepad: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      var checked = 0;
      for (final element in find.byType(Text).evaluate()) {
        final inherited = DefaultTextStyle.of(element).style;
        expect(
          inherited.decoration,
          anyOf(isNull, TextDecoration.none),
          reason: 'the ambient style must not underline the text',
        );
        checked++;
      }
      expect(checked, greaterThan(0), reason: 'no text was checked');
    });

    testWidgets('the shell provides a Material ancestor', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTdTheme(
            choice: AppThemeChoice.dark,
            platformBrightness: Brightness.dark,
          ),
          home: AppShell(
            section: AppSection.chat,
            onSectionChanged: (_) {},
            status: ConnectionStatus.connected,
            child: ChatScreen(
              entries: const <ChatEntry>[],
              status: ConnectionStatus.connected,
              onSend: (_) {},
              onSaveToNotepad: (_) {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Look from inside the shell: the shell creates the Material, so it has
      // to be *below* the shell and *above* its children.
      final context = tester.element(find.byType(ChatScreen));
      expect(
        Material.of(context),
        isNotNull,
        reason: 'a TextField needs a Material ancestor',
      );
    });
  });
}
