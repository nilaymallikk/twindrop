import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';

/// A flat toggle. Material's default switch would introduce a tinted track and
/// rounded Material look; this one uses `paper` when on and a hairline when off
/// (docs/13 §3). 48 dp tap target, keyboard operable.
class TdToggle extends StatelessWidget {
  const TdToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    this.disabledReason,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final enabled = onChanged != null;
    final trackColor = !enabled
        ? tokens.raised
        : value
            ? tokens.paper
            : tokens.surface;
    final knobColor = !enabled
        ? tokens.muted
        : value
            ? tokens.onPaper
            : tokens.muted;
    final side = context.tdControlHeight;

    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      hint: enabled ? null : disabledReason,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Container(
          constraints: BoxConstraints(minWidth: side, minHeight: side),
          color: const Color(0x00000000),
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: context.tdFast,
            curve: TdMotion.curve,
            width: 40,
            height: 22,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(TdRadius.md),
              border: Border.all(color: tokens.hairline, width: 1),
            ),
            child: AnimatedAlign(
              duration: context.tdFast,
              curve: TdMotion.curve,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: knobColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
