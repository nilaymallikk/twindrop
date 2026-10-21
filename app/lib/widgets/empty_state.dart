import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'buttons.dart';
import 'logo_mark.dart';

/// Empty state: the 24 px logo mark in `muted`, one plain sentence, and at
/// most one action. Left-aligned; no illustrations (docs/13 §6).
class TdEmptyState extends StatelessWidget {
  const TdEmptyState({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: TdSpace.s16,
        vertical: compact ? TdSpace.s20 : TdSpace.s32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const TdLogoMark(color: null, size: 24),
          const SizedBox(height: TdSpace.s12),
          Text(
            message,
            style: context.tdType.secondary.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: TdSpace.s16),
            Align(
              alignment: Alignment.centerLeft,
              child: TdButton(
                label: actionLabel!,
                onPressed: onAction,
                variant: TdButtonVariant.secondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
