import 'package:flutter/material.dart';
import 'package:twindrop_core/models/enums.dart';

/// Font families. Bundled by the app as assets (docs/13 §2); never fetched at
/// runtime. Referenced only from this file so no widget hard-codes a family.
abstract final class TdFonts {
  static const String sans = 'IBM Plex Sans';
  static const String mono = 'IBM Plex Mono';
}

/// The only file allowed to contain raw colour literals (DES-002, docs/13 §10).
///
/// Values come from `design/tokens.json`; the QR pair and the black-theme
/// extras are fixed in docs/13 §6 and the token note for the P1 black theme.
abstract final class TdPalette {
  /// Fully transparent. Lives here so no widget has to spell a colour literal
  /// (DES-002: the only file with colour literals).
  static const Color transparent = Color(0x00000000);

  // Dark (default).
  static const Color darkBg = Color(0xFF0E0F11);
  static const Color darkSurface = Color(0xFF16181B);
  static const Color darkRaised = Color(0xFF1D2024);
  static const Color darkHairline = Color(0xFF2A2E33);
  static const Color darkText = Color(0xFFECEBE6);
  static const Color darkTextSecondary = Color(0xFFB4B6BB);
  static const Color darkMuted = Color(0xFF8E9198);
  static const Color darkPaper = Color(0xFFECEBE6);
  static const Color darkOnPaper = Color(0xFF0E0F11);
  static const Color darkAccent = Color(0xFFFF6B3D);
  static const Color darkOnAccent = Color(0xFF0E0F11);
  static const Color darkOk = Color(0xFF5FBF8F);
  static const Color darkWarn = Color(0xFFE3A93B);
  static const Color darkError = Color(0xFFF2705F);
  static const Color darkScrim = Color(0xA0000000);

  // Light.
  static const Color lightBg = Color(0xFFF4F3EE);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightRaised = Color(0xFFEDECE6);
  static const Color lightHairline = Color(0xFFD8D6CE);
  static const Color lightText = Color(0xFF131417);
  static const Color lightTextSecondary = Color(0xFF3C4047);
  static const Color lightMuted = Color(0xFF5C6068);
  static const Color lightPaper = Color(0xFF131417);
  static const Color lightOnPaper = Color(0xFFF4F3EE);
  static const Color lightAccent = Color(0xFFB33F12);
  static const Color lightOnAccent = Color(0xFFFFFFFF);
  static const Color lightOk = Color(0xFF1E7A4F);
  static const Color lightWarn = Color(0xFF8A5A00);
  static const Color lightError = Color(0xFFB3261E);
  static const Color lightScrim = Color(0x66000000);

  // Black (P1 OLED): dark palette with a true-black background and near-black
  // surfaces (design/tokens.json -> color.black note).
  static const Color blackBg = Color(0xFF000000);
  static const Color blackSurface = Color(0xFF0B0B0C);

  // QR tile: always dark-on-light regardless of theme, so it scans reliably
  // (docs/13 §6 "QR"). Not part of tokens.json; recorded here as the only
  // source of these values.
  static const Color qrTile = Color(0xFFF4F3EE);
  static const Color qrInk = Color(0xFF131417);
}

/// 4 pt spacing grid (design/tokens.json -> spacing).
abstract final class TdSpace {
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s48 = 48;
}

/// Radii (design/tokens.json -> radius).
abstract final class TdRadius {
  static const double xs = 4;
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;

  static const Radius rXs = Radius.circular(xs);
  static const Radius rSm = Radius.circular(sm);
  static const Radius rMd = Radius.circular(md);
  static const Radius rLg = Radius.circular(lg);

  static const BorderRadius allXs = BorderRadius.all(rXs);
  static const BorderRadius allSm = BorderRadius.all(rSm);
  static const BorderRadius allMd = BorderRadius.all(rMd);
  static const BorderRadius allLg = BorderRadius.all(rLg);
}

/// Motion (design/tokens.json -> motion, docs/13 §7).
abstract final class TdMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration message = Duration(milliseconds: 140);
  static const Duration sheet = Duration(milliseconds: 180);
  static const double messageRise = 4;
  static const Curve curve = Curves.easeOut;
}

/// Breakpoints. Below this width the app uses the phone layout.
abstract final class TdBreakpoint {
  static const double phoneMax = 600;
  static const double chatColumnMax = 720;
}

/// Design tokens exposed to the widget tree as a [ThemeExtension].
///
/// Widgets read these through `context.td`; no widget may construct a colour
/// from a literal (docs/13 §10, DES-002).
@immutable
class TdTokens extends ThemeExtension<TdTokens> {
  const TdTokens({
    required this.choice,
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.raised,
    required this.hairline,
    required this.text,
    required this.textSecondary,
    required this.muted,
    required this.paper,
    required this.onPaper,
    required this.accent,
    required this.onAccent,
    required this.ok,
    required this.warn,
    required this.error,
    required this.scrim,
    required this.qrTile,
    required this.qrInk,
  });

  /// The theme variant this token set was resolved from.
  final AppThemeChoice choice;
  final Brightness brightness;

  final Color bg;
  final Color surface;
  final Color raised;
  final Color hairline;
  final Color text;
  final Color textSecondary;
  final Color muted;
  final Color paper;
  final Color onPaper;
  final Color accent;
  final Color onAccent;
  final Color ok;
  final Color warn;
  final Color error;
  final Color scrim;
  final Color qrTile;
  final Color qrInk;

  bool get isDark => brightness == Brightness.dark;

  /// Resolves the requested appearance. `system` follows [platformBrightness];
  /// dark stays the first-run default (docs/13 §1).
  static TdTokens resolve(
    AppThemeChoice choice,
    Brightness platformBrightness,
  ) {
    switch (choice) {
      case AppThemeChoice.light:
        return _light;
      case AppThemeChoice.dark:
        return _dark;
      case AppThemeChoice.black:
        return _black;
      case AppThemeChoice.system:
        return platformBrightness == Brightness.light ? _light : _dark;
    }
  }

  static const TdTokens _dark = TdTokens(
    choice: AppThemeChoice.dark,
    brightness: Brightness.dark,
    bg: TdPalette.darkBg,
    surface: TdPalette.darkSurface,
    raised: TdPalette.darkRaised,
    hairline: TdPalette.darkHairline,
    text: TdPalette.darkText,
    textSecondary: TdPalette.darkTextSecondary,
    muted: TdPalette.darkMuted,
    paper: TdPalette.darkPaper,
    onPaper: TdPalette.darkOnPaper,
    accent: TdPalette.darkAccent,
    onAccent: TdPalette.darkOnAccent,
    ok: TdPalette.darkOk,
    warn: TdPalette.darkWarn,
    error: TdPalette.darkError,
    scrim: TdPalette.darkScrim,
    qrTile: TdPalette.qrTile,
    qrInk: TdPalette.qrInk,
  );

  static const TdTokens _light = TdTokens(
    choice: AppThemeChoice.light,
    brightness: Brightness.light,
    bg: TdPalette.lightBg,
    surface: TdPalette.lightSurface,
    raised: TdPalette.lightRaised,
    hairline: TdPalette.lightHairline,
    text: TdPalette.lightText,
    textSecondary: TdPalette.lightTextSecondary,
    muted: TdPalette.lightMuted,
    paper: TdPalette.lightPaper,
    onPaper: TdPalette.lightOnPaper,
    accent: TdPalette.lightAccent,
    onAccent: TdPalette.lightOnAccent,
    ok: TdPalette.lightOk,
    warn: TdPalette.lightWarn,
    error: TdPalette.lightError,
    scrim: TdPalette.lightScrim,
    qrTile: TdPalette.qrTile,
    qrInk: TdPalette.qrInk,
  );

  static const TdTokens _black = TdTokens(
    choice: AppThemeChoice.black,
    brightness: Brightness.dark,
    bg: TdPalette.blackBg,
    surface: TdPalette.blackSurface,
    raised: TdPalette.darkRaised,
    hairline: TdPalette.darkHairline,
    text: TdPalette.darkText,
    textSecondary: TdPalette.darkTextSecondary,
    muted: TdPalette.darkMuted,
    paper: TdPalette.darkPaper,
    onPaper: TdPalette.darkOnPaper,
    accent: TdPalette.darkAccent,
    onAccent: TdPalette.darkOnAccent,
    ok: TdPalette.darkOk,
    warn: TdPalette.darkWarn,
    error: TdPalette.darkError,
    scrim: TdPalette.darkScrim,
    qrTile: TdPalette.qrTile,
    qrInk: TdPalette.qrInk,
  );

  @override
  TdTokens copyWith({
    AppThemeChoice? choice,
    Brightness? brightness,
    Color? bg,
    Color? surface,
    Color? raised,
    Color? hairline,
    Color? text,
    Color? textSecondary,
    Color? muted,
    Color? paper,
    Color? onPaper,
    Color? accent,
    Color? onAccent,
    Color? ok,
    Color? warn,
    Color? error,
    Color? scrim,
    Color? qrTile,
    Color? qrInk,
  }) {
    return TdTokens(
      choice: choice ?? this.choice,
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      raised: raised ?? this.raised,
      hairline: hairline ?? this.hairline,
      text: text ?? this.text,
      textSecondary: textSecondary ?? this.textSecondary,
      muted: muted ?? this.muted,
      paper: paper ?? this.paper,
      onPaper: onPaper ?? this.onPaper,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      ok: ok ?? this.ok,
      warn: warn ?? this.warn,
      error: error ?? this.error,
      scrim: scrim ?? this.scrim,
      qrTile: qrTile ?? this.qrTile,
      qrInk: qrInk ?? this.qrInk,
    );
  }

  @override
  TdTokens lerp(TdTokens? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return TdTokens(
      choice: t < 0.5 ? choice : other.choice,
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      raised: mix(raised, other.raised),
      hairline: mix(hairline, other.hairline),
      text: mix(text, other.text),
      textSecondary: mix(textSecondary, other.textSecondary),
      muted: mix(muted, other.muted),
      paper: mix(paper, other.paper),
      onPaper: mix(onPaper, other.onPaper),
      accent: mix(accent, other.accent),
      onAccent: mix(onAccent, other.onAccent),
      ok: mix(ok, other.ok),
      warn: mix(warn, other.warn),
      error: mix(error, other.error),
      scrim: mix(scrim, other.scrim),
      qrTile: mix(qrTile, other.qrTile),
      qrInk: mix(qrInk, other.qrInk),
    );
  }
}

/// Icon sizes used by the design system (outline icons; docs/13 §4).
abstract final class TdIconSizes {
  /// Delivery ticks (chat bubbles).
  static const double delivery = 14;

  /// Inline icons (buttons, meta rows).
  static const double sm = 16;

  /// Desktop action icons.
  static const double md = 20;

  /// Phone navigation icons.
  static const double lg = 24;

  /// Empty-state logo mark (docs/13 §6).
  static const double emptyMark = 24;
}
