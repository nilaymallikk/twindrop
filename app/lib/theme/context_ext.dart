import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Convenience accessors for the design system. Widgets use these instead of
/// reaching for literals or `Theme.of(...)` internals.
extension TdContext on BuildContext {
  /// Design tokens for the current theme.
  TdTokens get td => Theme.of(this).extension<TdTokens>()!;

  /// Type scale for the current theme.
  TdType get tdType => Theme.of(this).extension<TdType>()!;

  /// True below [TdBreakpoint.phoneMax]; drives phone vs desktop layout.
  bool get tdIsPhone => MediaQuery.sizeOf(this).width < TdBreakpoint.phoneMax;

  /// True when the OS asks to reduce motion (DES-008).
  bool get tdReduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;

  /// Current user font scale relative to 1.0 (system text size).
  double get tdTextScale => MediaQuery.textScalerOf(this).scale(14) / 14;

  /// Body style for the current width class.
  TextStyle get tdBody => tdType.bodyFor(tdIsPhone);

  /// A fast state-change duration, or zero when motion is reduced.
  Duration get tdFast => tdReduceMotion ? Duration.zero : TdMotion.fast;

  /// Sheet/popup duration, or zero when motion is reduced.
  Duration get tdSheet => tdReduceMotion ? Duration.zero : TdMotion.sheet;

  /// Focus ring colour (accent is allowed for focus; docs/13 §1).
  Color get tdFocusColor => td.accent;

  /// True on touch platforms, where controls use the comfortable 48 dp height
  /// (docs/13 §3 "Density"). Layout (phone vs desktop) still follows width.
  bool get tdMobilePlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Control height: 48 dp on touch platforms, 36 px on desktop.
  double get tdControlHeight => tdMobilePlatform ? 48 : 36;
}

/// Semantic text styles that depend on tokens, kept here so screens express
/// intent (e.g. "meta") rather than colour/size combinations.
extension TdStyles on TextStyle {
  /// Meta text: mono 12, muted.
  static TextStyle metaOf(BuildContext context) => context.tdType.meta;

  /// Secondary copy: sans 13, textSecondary.
  static TextStyle secondaryOf(BuildContext context) => context.tdType.secondary;
}
