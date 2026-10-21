import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';

/// Bottom-edge countdown bar used by the Android share panel's 4 s auto-dismiss
/// (docs/13 §6). Accent is allowed here as a progress/selection indicator.
///
/// Motion is omitted when the OS asks to reduce motion; the completion callback
/// still fires so auto-dismiss keeps working.
class TdCountdownHairline extends StatefulWidget {
  const TdCountdownHairline({
    super.key,
    required this.duration,
    this.onComplete,
    this.height = 2,
    this.color,
  });

  final Duration duration;
  final VoidCallback? onComplete;
  final double height;
  final Color? color;

  @override
  State<TdCountdownHairline> createState() => _TdCountdownHairlineState();
}

class _TdCountdownHairlineState extends State<TdCountdownHairline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _controller.duration = context.tdReduceMotion
        ? Duration.zero
        : widget.duration;
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) widget.onComplete?.call();
    });
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final remaining = (1 - _controller.value).clamp(0.0, 1.0);
          return Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: remaining,
              child: ColoredBox(
                color: widget.color ?? tokens.accent,
                child: SizedBox(height: widget.height, width: double.infinity),
              ),
            ),
          );
        },
      ),
    );
  }
}
