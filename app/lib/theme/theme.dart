import 'package:flutter/material.dart';
import 'package:twindrop_core/models/enums.dart';

import 'tokens.dart';
import 'typography.dart';

/// Builds the app [ThemeData] for a resolved appearance choice.
///
/// All Material 3 defaults that would introduce depth or motion are overridden
/// (docs/13 §10): flat surfaces, no tint, no splash, hairline dividers, fade
/// page transitions.
ThemeData buildTdTheme({
  required AppThemeChoice choice,
  required Brightness platformBrightness,
}) {
  final tokens = TdTokens.resolve(choice, platformBrightness);
  return buildTdThemeFromTokens(tokens);
}

/// Same as [buildTdTheme], for callers that already resolved tokens (tests,
/// golden harnesses, theme previews).
ThemeData buildTdThemeFromTokens(TdTokens tokens) {
  final type = TdType.fromTokens(tokens);
  final transparent = tokens.surface.withValues(alpha: 0);
  final scheme = ColorScheme(
    brightness: tokens.brightness,
    primary: tokens.accent,
    onPrimary: tokens.onAccent,
    secondary: tokens.paper,
    onSecondary: tokens.onPaper,
    error: tokens.error,
    onError: tokens.bg,
    surface: tokens.surface,
    onSurface: tokens.text,
    surfaceContainerHighest: tokens.raised,
    onSurfaceVariant: tokens.textSecondary,
    outline: tokens.hairline,
    outlineVariant: tokens.hairline,
    shadow: transparent,
    scrim: tokens.scrim,
    inverseSurface: tokens.paper,
    onInverseSurface: tokens.onPaper,
    inversePrimary: tokens.accent,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: tokens.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.bg,
    canvasColor: tokens.bg,
    fontFamily: TdFonts.sans,
    splashFactory: NoSplash.splashFactory,
    splashColor: transparent,
    highlightColor: transparent,
    hoverColor: tokens.raised,
    focusColor: tokens.accent,
    dividerColor: tokens.hairline,
    disabledColor: tokens.muted,
    extensions: <ThemeExtension<dynamic>>[tokens, type],
    textTheme: TextTheme(
      displaySmall: type.screen,
      headlineMedium: type.screen,
      headlineSmall: type.title,
      titleLarge: type.title,
      titleMedium: type.title,
      titleSmall: type.label,
      bodyLarge: type.bodyPhone,
      bodyMedium: type.body,
      bodySmall: type.secondary,
      labelLarge: type.label,
      labelMedium: type.label,
      labelSmall: type.meta,
    ),
    primaryTextTheme: TextTheme(
      titleLarge: type.title.copyWith(color: tokens.onAccent),
      bodyMedium: type.body.copyWith(color: tokens.onAccent),
      labelLarge: type.label.copyWith(color: tokens.onAccent),
    ),
    iconTheme: IconThemeData(color: tokens.text, size: TdIconSizes.md),
    dividerTheme: DividerThemeData(
      color: tokens.hairline,
      thickness: 1,
      space: 1,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.accent,
      selectionColor: tokens.accent.withValues(alpha: 0.30),
      selectionHandleColor: tokens.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.surface,
      isDense: true,
      hintStyle: type.body.copyWith(color: tokens.muted),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: TdSpace.s12,
        vertical: TdSpace.s12,
      ),
      border: OutlineInputBorder(
        borderRadius: TdRadius.allMd,
        borderSide: BorderSide(color: tokens.hairline, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: TdRadius.allMd,
        borderSide: BorderSide(color: tokens.hairline, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: TdRadius.allMd,
        borderSide: BorderSide(color: tokens.accent, width: 1),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: TdRadius.allMd,
        borderSide: BorderSide(color: tokens.error, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: TdRadius.allMd,
        borderSide: BorderSide(color: tokens.error, width: 1),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: TdFadePageTransitionsBuilder(),
        TargetPlatform.linux: TdFadePageTransitionsBuilder(),
        TargetPlatform.fuchsia: TdFadePageTransitionsBuilder(),
        TargetPlatform.iOS: TdFadePageTransitionsBuilder(),
        TargetPlatform.macOS: TdFadePageTransitionsBuilder(),
        TargetPlatform.windows: TdFadePageTransitionsBuilder(),
      },
    ),
  );
}

/// Fade-only page transition; instant when the OS asks to reduce motion
/// (docs/13 §7).
class TdFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const TdFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return child;
    }
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: TdMotion.curve,
        reverseCurve: TdMotion.curve,
      ),
      child: child,
    );
  }
}
