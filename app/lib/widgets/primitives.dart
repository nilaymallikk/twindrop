import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';

/// A 1 px divider. Depth in TwinDrop is a hairline plus a surface step, never a
/// shadow (docs/13 §3).
class TdHairline extends StatelessWidget {
  const TdHairline({super.key, this.vertical = false, this.color});

  final bool vertical;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final lineColor = color ?? context.td.hairline;
    if (vertical) {
      return SizedBox(width: 1, child: ColoredBox(color: lineColor));
    }
    return SizedBox(height: 1, child: ColoredBox(color: lineColor));
  }
}

/// A flat panel: `surface` (or `raised`) fill, optional 1 px hairline, radius
/// from the token scale. The building block for cards, sheets and popovers.
class TdSurface extends StatelessWidget {
  const TdSurface({
    super.key,
    required this.child,
    this.color,
    this.radius = TdRadius.md,
    this.border = true,
    this.borderColor,
    this.padding,
    this.width,
    this.height,
  });

  final Widget child;
  final Color? color;
  final double radius;
  final bool border;
  final Color? borderColor;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? tokens.surface,
        borderRadius: BorderRadius.circular(radius),
        border: border
            ? Border.all(color: borderColor ?? tokens.hairline, width: 1)
            : null,
      ),
      child: child,
    );
  }
}

/// Content column widths for desktop screens. Keeps chat at 720 px and forms
/// readable, while allowing the notepad to use more room.
abstract final class TdContentWidth {
  static const double chat = TdBreakpoint.chatColumnMax;
  static const double form = 640;
  static const double settings = 720;
}
