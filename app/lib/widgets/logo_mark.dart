import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';

/// The TwinDrop mark (design/logo-mark.svg): two overlapping rounded squares —
/// the back one outlined, the front one solid — with an accent square in the
/// front square's lower-right corner.
///
/// Painted, not loaded: the mark must render offline and without an asset
/// (docs/13 §5). Empty states use it at 24 px in `muted`.
class TdLogoMark extends StatelessWidget {
  const TdLogoMark({
    super.key,
    this.size = TdIconSizes.emptyMark,
    this.color,
    this.dropColor,
    this.semanticLabel,
  });

  final double size;

  /// Colour of the two squares. Defaults to `muted`, per the empty-state rule.
  final Color? color;

  /// Colour of the small square. Defaults to the same [color] so a muted mark
  /// stays monochrome; pass `accent` where the mark is the product identity.
  final Color? dropColor;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? context.td.muted;
    final mark = SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _TdLogoPainter(
          color: resolvedColor,
          dropColor: dropColor ?? resolvedColor,
        ),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: mark);
    return Semantics(label: semanticLabel, image: true, child: mark);
  }
}

class _TdLogoPainter extends CustomPainter {
  const _TdLogoPainter({required this.color, required this.dropColor});

  final Color color;
  final Color dropColor;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 64;
    canvas.save();
    canvas.scale(scale, scale);

    final outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(6, 6, 38, 38),
        const Radius.circular(7),
      ),
      outline,
    );

    final solid = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(20, 20, 38, 38),
        const Radius.circular(7),
      ),
      solid,
    );

    final drop = Paint()
      ..color = dropColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(42, 42, 8, 8),
        const Radius.circular(2),
      ),
      drop,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TdLogoPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dropColor != dropColor;
}
