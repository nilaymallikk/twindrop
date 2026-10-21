import 'package:flutter/material.dart';

import 'tokens.dart';

/// The TwinDrop type scale (design/tokens.json -> type.scale, docs/13 §2).
///
/// Sizes and line heights are taken from the token file; `height` is expressed
/// as a multiple because Flutter styles line height that way.
@immutable
class TdType extends ThemeExtension<TdType> {
  const TdType({
    required this.meta,
    required this.secondary,
    required this.body,
    required this.bodyPhone,
    required this.title,
    required this.screen,
    required this.label,
    required this.code,
    required this.mono,
  });

  /// Mono 12/16 — timestamps, device names, counts, tags.
  final TextStyle meta;

  /// Sans 13/18 — supporting copy.
  final TextStyle secondary;

  /// Sans 14/20 — desktop body.
  final TextStyle body;

  /// Sans 15/22 — phone body.
  final TextStyle bodyPhone;

  /// Sans 17/24 semibold — card and sheet titles.
  final TextStyle title;

  /// Sans 22/28 semibold — screen titles.
  final TextStyle screen;

  /// Sans 14/20 medium — button labels.
  final TextStyle label;

  /// Mono 32, +0.12 em — pairing confirmation code.
  final TextStyle code;

  /// Mono 14/20 — inline monospace body (diagnostics values, command lines).
  final TextStyle mono;

  /// Builds the scale for a resolved [TdTokens] set.
  factory TdType.fromTokens(TdTokens tokens) {
    final base = TextStyle(color: tokens.text);
    TextStyle sans({
      required double size,
      required double height,
      required FontWeight weight,
      double letterSpacing = 0,
      Color? color,
    }) =>
        base.copyWith(
          fontFamily: TdFonts.sans,
          fontSize: size,
          height: height / size,
          fontWeight: weight,
          letterSpacing: letterSpacing,
          color: color,
        );
    TextStyle mono({
      required double size,
      required double height,
      double letterSpacing = 0,
      Color? color,
    }) =>
        base.copyWith(
          fontFamily: TdFonts.mono,
          fontSize: size,
          height: height / size,
          fontWeight: FontWeight.w400,
          letterSpacing: letterSpacing,
          color: color,
        );

    return TdType(
      meta: mono(size: 12, height: 16, color: tokens.muted),
      secondary: sans(
        size: 13,
        height: 18,
        weight: FontWeight.w400,
        color: tokens.textSecondary,
      ),
      body: sans(size: 14, height: 20, weight: FontWeight.w400),
      bodyPhone: sans(size: 15, height: 22, weight: FontWeight.w400),
      title: sans(
        size: 17,
        height: 24,
        weight: FontWeight.w600,
        letterSpacing: -0.17, // -0.01 em
      ),
      screen: sans(
        size: 22,
        height: 28,
        weight: FontWeight.w600,
        letterSpacing: -0.22, // -0.01 em
      ),
      label: sans(size: 14, height: 20, weight: FontWeight.w500),
      code: mono(size: 32, height: 40, letterSpacing: 3.84), // +0.12 em
      mono: mono(size: 14, height: 20),
    );
  }

  /// Body style for the current width class.
  TextStyle bodyFor(bool phone) => phone ? bodyPhone : body;

  TdType copyWith({
    TextStyle? meta,
    TextStyle? secondary,
    TextStyle? body,
    TextStyle? bodyPhone,
    TextStyle? title,
    TextStyle? screen,
    TextStyle? label,
    TextStyle? code,
    TextStyle? mono,
  }) {
    return TdType(
      meta: meta ?? this.meta,
      secondary: secondary ?? this.secondary,
      body: body ?? this.body,
      bodyPhone: bodyPhone ?? this.bodyPhone,
      title: title ?? this.title,
      screen: screen ?? this.screen,
      label: label ?? this.label,
      code: code ?? this.code,
      mono: mono ?? this.mono,
    );
  }

  @override
  TdType lerp(TdType? other, double t) {
    if (other == null) return this;
    TextStyle mix(TextStyle a, TextStyle b) =>
        TextStyle.lerp(a, b, t) ?? a;
    return TdType(
      meta: mix(meta, other.meta),
      secondary: mix(secondary, other.secondary),
      body: mix(body, other.body),
      bodyPhone: mix(bodyPhone, other.bodyPhone),
      title: mix(title, other.title),
      screen: mix(screen, other.screen),
      label: mix(label, other.label),
      code: mix(code, other.code),
      mono: mix(mono, other.mono),
    );
  }
}
