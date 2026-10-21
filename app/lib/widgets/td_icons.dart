import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';

/// One outline icon: SVG path data drawn on a 24×24 grid with a 1.5 stroke.
///
/// The set is bundled with the app as path data so TwinDrop never fetches an
/// icon font or an asset at runtime, and so the whole UI uses one icon style
/// (docs/13 §4). Paths follow the Lucide geometry.
@immutable
class TdIconData {
  const TdIconData(this.pathData);

  final String pathData;

  @override
  bool operator ==(Object other) =>
      other is TdIconData && other.pathData == pathData;

  @override
  int get hashCode => pathData.hashCode;
}

/// The TwinDrop outline icon set. Lucide-style geometry, single family.
abstract final class TdIcons {
  static const TdIconData check = TdIconData('M20 6 9 17 4 12');
  static const TdIconData checkCheck = TdIconData(
    'M18 6 7 17 2 12 M22 10 13 19 11 17',
  );
  static const TdIconData clock = TdIconData(
    'M12 2a10 10 0 1 0 0 20 10 10 0 1 0 0-20 M12 7v5l3 2',
  );
  static const TdIconData send = TdIconData(
    'M22 2 11 13 M22 2 15 22 11 13 2 9 22 2',
  );
  static const TdIconData search = TdIconData(
    'M11 3a8 8 0 1 0 0 16 8 8 0 1 0 0-16 M21 21l-4.3-4.3',
  );
  static const TdIconData plus = TdIconData('M12 5v14 M5 12h14');
  static const TdIconData pin = TdIconData(
    'M9 3h6 M10 3v6l-3 4h10l-3-4V3 M12 13v8',
  );
  static const TdIconData moreHorizontal = TdIconData(
    'M4 12h.01 M12 12h.01 M20 12h.01',
  );
  static const TdIconData close = TdIconData('M18 6 6 18 M6 6l12 12');
  static const TdIconData chevronDown = TdIconData('m6 9 6 6 6-6');
  static const TdIconData chevronRight = TdIconData('m9 18 6-6-6-6');
  static const TdIconData chevronLeft = TdIconData('m15 18-6-6 6-6');
  static const TdIconData arrowDown = TdIconData('M12 5v14 M19 12l-7 7-7-7');
  static const TdIconData arrowLeft = TdIconData('M19 12H5 M12 19l-7-7 7-7');
  static const TdIconData arrowUp = TdIconData('M12 19V5 M5 12l7-7 7 7');
  static const TdIconData link = TdIconData(
    'M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71 '
    'M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71',
  );
  static const TdIconData copy = TdIconData('M8 8h12v12H8z M16 8V4H4v12h4');
  static const TdIconData trash = TdIconData(
    'M3 6h18 M8 6V4h8v2 M19 6l-1 14H6L5 6 M10 11v6 M14 11v6',
  );
  static const TdIconData edit = TdIconData(
    'M17 3a2.83 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5z',
  );
  static const TdIconData refresh = TdIconData(
    'M21 2v6h-6 M3 12a9 9 0 0 1 15-6.7L21 8 '
    'M3 22v-6h6 M21 12a9 9 0 0 1-15 6.7L3 16',
  );
  static const TdIconData settings = TdIconData(
    'M4 21v-7 M4 10V3 M12 21v-9 M12 8V3 M20 21v-5 M20 12V3 '
    'M1 14h6 M9 8h6 M17 16h6',
  );
  static const TdIconData chat = TdIconData(
    'M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z',
  );
  static const TdIconData note = TdIconData(
    'M5 3h11l3 3v15H5z M16 3v4h4 M9 12h7 M9 16h4',
  );
  static const TdIconData openExternal = TdIconData(
    'M15 3h6v6 M10 14 21 3 '
    'M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6',
  );
  static const TdIconData monitor = TdIconData(
    'M3 4h18v12H3z M8 20h8 M12 16v4',
  );
  static const TdIconData phone = TdIconData(
    'M7 2h10a2 2 0 0 1 2 2v16a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z '
    'M11 18h2',
  );
  static const TdIconData alert = TdIconData(
    'M12 2a10 10 0 1 0 0 20 10 10 0 1 0 0-20 M12 8v5 M12 16h.01',
  );
  static const TdIconData wifi = TdIconData(
    'M2 8.8a16 16 0 0 1 20 0 M5 12.5a11 11 0 0 1 14 0 '
    'M8.5 16a6 6 0 0 1 7 0 M12 20h.01',
  );
  static const TdIconData undo = TdIconData(
    'M3 7v6h6 M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13',
  );
  static const TdIconData folder = TdIconData('M3 6h6l2 2h10v11H3z');
  static const TdIconData shield = TdIconData(
    'M12 2 4 6v6c0 5 3.5 8.5 8 10 4.5-1.5 8-5 8-10V6z',
  );
  static const TdIconData terminal = TdIconData(
    'M4 4h16v16H4z M8 9l3 3-3 3 M13 15h4',
  );
  static const TdIconData image = TdIconData(
    'M3 3h18v18H3z M8 11a2 2 0 1 0 0-4 2 2 0 0 0 0 4 '
    'M21 15l-5-5L5 21',
  );
  static const TdIconData select = TdIconData('M4 4h16v16H4z M8 12l3 3 6-6');
  static const TdIconData logout = TdIconData(
    'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4 M16 17l5-5-5-5 M21 12H9',
  );
  static const TdIconData lock = TdIconData(
    'M7 11V8a5 5 0 0 1 10 0v3 M5 11h14v10H5z',
  );
  static const TdIconData bell = TdIconData(
    'M6 8a6 6 0 0 1 12 0c0 7 2 7 2 9H4c0-2 2-2 2-9 M10 21h4',
  );
  static const TdIconData clipboard = TdIconData(
    'M9 2h6v4H9z M7 4h10a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6'
    'a2 2 0 0 1 2-2z',
  );
  static const TdIconData download = TdIconData(
    'M12 3v12 M7 10l5 5 5-5 M4 21h16',
  );
  static const TdIconData filter = TdIconData('M3 5h18l-7 8v6l-4 2v-8z');
  static const TdIconData grip = TdIconData(
    'M9 5h.01 M9 12h.01 M9 19h.01 M15 5h.01 M15 12h.01 M15 19h.01',
  );

  /// Viewfinder corners plus a scan line — used by the pairing scanner.
  static const TdIconData scan = TdIconData(
    'M3 7V5a2 2 0 0 1 2-2h2 M17 3h2a2 2 0 0 1 2 2v2 '
    'M21 17v2a2 2 0 0 1-2 2h-2 M7 21H5a2 2 0 0 1-2-2v-2 M7 12h10',
  );

  /// Torch for the camera preview.
  static const TdIconData flashlight = TdIconData(
    'M6 9h6 M6 12h6 M13 5h4a2 2 0 0 1 2 2v3a2 2 0 0 1-2 2h-4Z '
    'M6 15h6 M13 15v6 M11 15v6 M9 15v6 M7 15v6',
  );
}

/// Renders a [TdIconData] with the design-system stroke.
class TdIcon extends StatelessWidget {
  const TdIcon(
    this.data, {
    super.key,
    this.size = TdIconSizes.md,
    this.color,
    this.semanticLabel,
  });

  final TdIconData data;
  final double size;
  final Color? color;

  /// When set, the icon is announced to screen readers. Icons that merely
  /// decorate a labelled control leave this null and are excluded.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? IconTheme.of(context).color ?? context.td.text;
    final painter = _TdIconPainter(data: data, color: resolved);
    final icon = SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: painter, isComplex: false),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: icon);
    return Semantics(label: semanticLabel, child: icon);
  }
}

class _TdIconPainter extends CustomPainter {
  const _TdIconPainter({required this.data, required this.color});

  final TdIconData data;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    canvas.save();
    canvas.scale(scale, scale);
    canvas.drawPath(_parseSvgPath(data.pathData), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TdIconPainter oldDelegate) =>
      oldDelegate.data != data || oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Minimal SVG path parser (absolute + relative M L H V C S Q T A Z). Enough for
// the outline icon set above; no external package, no runtime fetch.
// ---------------------------------------------------------------------------

Path _parseSvgPath(String source) {
  final reader = _PathReader(source);
  return reader.parse();
}

class _PathReader {
  _PathReader(this.source);

  final String source;
  int _i = 0;

  bool get _atEnd => _i >= source.length;

  void _skipSeparators() {
    while (!_atEnd) {
      final c = source.codeUnitAt(_i);
      if (c == 0x20 || c == 0x2C || c == 0x09 || c == 0x0A || c == 0x0D) {
        _i++;
      } else {
        return;
      }
    }
  }

  bool _startsNumber() {
    if (_atEnd) return false;
    final c = source[_i];
    return c == '-' || c == '+' || c == '.' || _isDigit(c);
  }

  static bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 0x30 && u <= 0x39;
  }

  static bool _isCommand(String c) => 'MmLlHhVvCcSsQqTtAaZz'.contains(c);

  double _readNumber() {
    _skipSeparators();
    final start = _i;
    if (!_atEnd && (source[_i] == '-' || source[_i] == '+')) _i++;
    var seenDot = false;
    while (!_atEnd) {
      final c = source[_i];
      if (_isDigit(c)) {
        _i++;
      } else if (c == '.' && !seenDot) {
        seenDot = true;
        _i++;
      } else {
        break;
      }
    }
    // Exponent (rare in icon paths, supported for completeness).
    if (!_atEnd && (source[_i] == 'e' || source[_i] == 'E')) {
      final save = _i;
      _i++;
      if (!_atEnd && (source[_i] == '-' || source[_i] == '+')) _i++;
      var any = false;
      while (!_atEnd && _isDigit(source[_i])) {
        _i++;
        any = true;
      }
      if (!any) _i = save;
    }
    final text = source.substring(start, _i);
    final value = double.tryParse(text);
    if (value == null) {
      throw FormatException('Bad number in icon path: "$text"');
    }
    return value;
  }

  Path parse() {
    final path = Path();
    double cx = 0;
    double cy = 0;
    double startX = 0;
    double startY = 0;
    double? lastCtrlX;
    double? lastCtrlY;
    String? previousCommand;

    while (true) {
      _skipSeparators();
      if (_atEnd) break;
      final char = source[_i];
      String command;
      if (_isCommand(char)) {
        command = char;
        _i++;
      } else if (previousCommand != null) {
        command = previousCommand;
      } else {
        break;
      }
      final upper = command.toUpperCase();
      final relative = command != upper;

      switch (upper) {
        case 'M':
          final p = _readPoint(relative, cx, cy);
          path.moveTo(p.$1, p.$2);
          cx = p.$1;
          cy = p.$2;
          startX = cx;
          startY = cy;
          // Further coordinate pairs after a moveto are implicit linetos.
          while (true) {
            _skipSeparators();
            if (!_startsNumber()) break;
            final q = _readPoint(relative, cx, cy);
            path.lineTo(q.$1, q.$2);
            cx = q.$1;
            cy = q.$2;
          }
          previousCommand = relative ? 'l' : 'L';
          continue;
        case 'L':
          while (true) {
            _skipSeparators();
            if (!_startsNumber()) break;
            final p = _readPoint(relative, cx, cy);
            path.lineTo(p.$1, p.$2);
            cx = p.$1;
            cy = p.$2;
          }
          lastCtrlX = null;
        case 'H':
          while (true) {
            _skipSeparators();
            if (!_startsNumber()) break;
            final x = _readNumber();
            final targetX = relative ? cx + x : x;
            path.lineTo(targetX, cy);
            cx = targetX;
          }
          lastCtrlX = null;
        case 'V':
          while (true) {
            _skipSeparators();
            if (!_startsNumber()) break;
            final y = _readNumber();
            final targetY = relative ? cy + y : y;
            path.lineTo(cx, targetY);
            cy = targetY;
          }
          lastCtrlX = null;
        case 'C':
          while (true) {
            _skipSeparators();
            if (!_startsNumber()) break;
            final c1 = _readPoint(relative, cx, cy);
            final c2 = _readPoint(relative, cx, cy);
            final end = _readPoint(relative, cx, cy);
            path.cubicTo(c1.$1, c1.$2, c2.$1, c2.$2, end.$1, end.$2);
            lastCtrlX = c2.$1;
            lastCtrlY = c2.$2;
            cx = end.$1;
            cy = end.$2;
          }
        case 'S':
          while (true) {
            _skipSeparators();
            if (!_startsNumber()) break;
            final c1x = lastCtrlX == null ? cx : cx * 2 - lastCtrlX;
            final c1y = lastCtrlY == null ? cy : cy * 2 - lastCtrlY;
            final c2 = _readPoint(relative, cx, cy);
            final end = _readPoint(relative, cx, cy);
            path.cubicTo(c1x, c1y, c2.$1, c2.$2, end.$1, end.$2);
            lastCtrlX = c2.$1;
            lastCtrlY = c2.$2;
            cx = end.$1;
            cy = end.$2;
          }
        case 'Q':
          while (true) {
            _skipSeparators();
            if (!_startsNumber()) break;
            final c = _readPoint(relative, cx, cy);
            final end = _readPoint(relative, cx, cy);
            path.quadraticBezierTo(c.$1, c.$2, end.$1, end.$2);
            lastCtrlX = c.$1;
            lastCtrlY = c.$2;
            cx = end.$1;
            cy = end.$2;
          }
        case 'T':
          while (true) {
            _skipSeparators();
            if (!_startsNumber()) break;
            final c1x = lastCtrlX == null ? cx : cx * 2 - lastCtrlX;
            final c1y = lastCtrlY == null ? cy : cy * 2 - lastCtrlY;
            final end = _readPoint(relative, cx, cy);
            path.quadraticBezierTo(c1x, c1y, end.$1, end.$2);
            lastCtrlX = c1x;
            lastCtrlY = c1y;
            cx = end.$1;
            cy = end.$2;
          }
        case 'A':
          while (true) {
            _skipSeparators();
            if (!_startsNumber()) break;
            final rx = _readNumber();
            final ry = _readNumber();
            final rotation = _readNumber();
            final largeArc = _readNumber() != 0;
            final sweep = _readNumber() != 0;
            final end = _readPoint(relative, cx, cy);
            _appendArc(
              path,
              fromX: cx,
              fromY: cy,
              rx: rx,
              ry: ry,
              rotationDeg: rotation,
              largeArc: largeArc,
              sweep: sweep,
              toX: end.$1,
              toY: end.$2,
            );
            cx = end.$1;
            cy = end.$2;
            lastCtrlX = null;
          }
        case 'Z':
          path.close();
          cx = startX;
          cy = startY;
          lastCtrlX = null;
        default:
          previousCommand = null;
          continue;
      }
      previousCommand = command;
    }
    return path;
  }

  (double, double) _readPoint(bool relative, double cx, double cy) {
    final x = _readNumber();
    final y = _readNumber();
    return relative ? (cx + x, cy + y) : (x, y);
  }

  /// Endpoint-parameterised elliptical arc -> cubic segments (SVG spec F.6).
  void _appendArc(
    Path path, {
    required double fromX,
    required double fromY,
    required double rx,
    required double ry,
    required double rotationDeg,
    required bool largeArc,
    required bool sweep,
    required double toX,
    required double toY,
  }) {
    if (rx == 0 || ry == 0) {
      path.lineTo(toX, toY);
      return;
    }
    rx = rx.abs();
    ry = ry.abs();
    final phi = rotationDeg * math.pi / 180;
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);
    final dx2 = (fromX - toX) / 2;
    final dy2 = (fromY - toY) / 2;
    final x1p = cosPhi * dx2 + sinPhi * dy2;
    final y1p = -sinPhi * dx2 + cosPhi * dy2;

    var rxSq = rx * rx;
    var rySq = ry * ry;
    final lambda = x1p * x1p / rxSq + y1p * y1p / rySq;
    if (lambda > 1) {
      final factor = math.sqrt(lambda);
      rx *= factor;
      ry *= factor;
      rxSq = rx * rx;
      rySq = ry * ry;
    }

    final denom = rxSq * y1p * y1p + rySq * x1p * x1p;
    var factor = 0.0;
    if (denom != 0) {
      final value = (rxSq * rySq - rxSq * y1p * y1p - rySq * x1p * x1p) / denom;
      factor = math.sqrt(math.max(0, value));
    }
    if (largeArc == sweep) factor = -factor;
    final cxp = factor * rx * y1p / ry;
    final cyp = -factor * ry * x1p / rx;
    final centerX = cosPhi * cxp - sinPhi * cyp + (fromX + toX) / 2;
    final centerY = sinPhi * cxp + cosPhi * cyp + (fromY + toY) / 2;

    final ux = (x1p - cxp) / rx;
    final uy = (y1p - cyp) / ry;
    final vx = (-x1p - cxp) / rx;
    final vy = (-y1p - cyp) / ry;
    var startAngle = math.atan2(uy, ux);
    var delta = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy);
    if (!sweep && delta > 0) delta -= 2 * math.pi;
    if (sweep && delta < 0) delta += 2 * math.pi;

    final segmentCount = (delta.abs() / (math.pi / 2)).ceil().clamp(1, 4);
    final segmentAngle = delta / segmentCount;
    final handle = 4 / 3 * math.tan(segmentAngle / 4);

    double pointX(double angle) =>
        cosPhi * rx * math.cos(angle) - sinPhi * ry * math.sin(angle) + centerX;
    double pointY(double angle) =>
        sinPhi * rx * math.cos(angle) + cosPhi * ry * math.sin(angle) + centerY;
    double derivX(double angle) =>
        -cosPhi * rx * math.sin(angle) - sinPhi * ry * math.cos(angle);
    double derivY(double angle) =>
        -sinPhi * rx * math.sin(angle) + cosPhi * ry * math.cos(angle);

    var angle = startAngle;
    for (var i = 0; i < segmentCount; i++) {
      final next = angle + segmentAngle;
      final p1x = pointX(angle);
      final p1y = pointY(angle);
      final p2x = pointX(next);
      final p2y = pointY(next);
      final c1x = p1x + handle * derivX(angle);
      final c1y = p1y + handle * derivY(angle);
      final c2x = p2x - handle * derivX(next);
      final c2y = p2y - handle * derivY(next);
      path.cubicTo(c1x, c1y, c2x, c2y, p2x, p2y);
      angle = next;
    }
  }
}
