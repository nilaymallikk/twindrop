import 'dart:async';

import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'buttons.dart';
import 'countdown_hairline.dart';

/// Undo affordance for destructive actions that are applied immediately (note
/// delete, share). Lives above the bottom edge; dismissed by the timer, by
/// Undo, or by the host replacing it.
class TdUndoBar extends StatefulWidget {
  const TdUndoBar({
    super.key,
    required this.message,
    required this.onAction,
    this.actionLabel = 'Undo',
    this.onDismissed,
    this.duration = const Duration(seconds: 5),
    this.showCountdown = true,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback? onDismissed;
  final Duration duration;
  final bool showCountdown;

  @override
  State<TdUndoBar> createState() => _TdUndoBarState();
}

class _TdUndoBarState extends State<TdUndoBar> {
  Timer? _timer;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _expire);
  }

  void _expire() {
    if (_handled || !mounted) return;
    _handled = true;
    widget.onDismissed?.call();
  }

  void _action() {
    if (_handled) return;
    _handled = true;
    _timer?.cancel();
    widget.onAction();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return Padding(
      padding: const EdgeInsets.all(TdSpace.s12),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: tokens.raised,
          borderRadius: TdRadius.allMd,
          border: Border.all(color: tokens.hairline, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TdSpace.s12,
                      vertical: TdSpace.s8,
                    ),
                    child: Text(
                      widget.message,
                      style: type.secondary.copyWith(
                        color: tokens.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: TdSpace.s8),
                  child: TdInlineAction(
                    label: widget.actionLabel,
                    onPressed: _action,
                  ),
                ),
              ],
            ),
            if (widget.showCountdown)
              TdCountdownHairline(
                duration: widget.duration,
                height: 2,
              ),
          ],
        ),
      ),
    );
  }
}
