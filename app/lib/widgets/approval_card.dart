import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'buttons.dart';
import 'confirmation_code.dart';
import 'primitives.dart';

/// Desktop approval card: the requesting device's name and platform, the shared
/// confirmation code, and Approve / Decline (PAIR-003). Declining or approving
/// is a real decision, so both actions are always available and clearly
/// labelled; no bypass exists.
class TdApprovalCard extends StatelessWidget {
  const TdApprovalCard({
    super.key,
    required this.deviceName,
    required this.platformLabel,
    required this.code,
    required this.onApprove,
    required this.onDecline,
    this.busy = false,
  });

  final String deviceName;
  final String platformLabel;
  final String code;
  final VoidCallback onApprove;
  final VoidCallback onDecline;

  /// While a decision is in flight both actions are disabled with a reason.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    final busyReason = busy ? 'Finishing the last step.' : null;

    return TdSurface(
      color: tokens.raised,
      radius: TdRadius.md,
      padding: const EdgeInsets.all(TdSpace.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('Pairing request', style: type.title),
          const SizedBox(height: TdSpace.s12),
          _DetailRow(label: 'Device', value: deviceName, mono: false),
          const SizedBox(height: TdSpace.s4),
          _DetailRow(label: 'Platform', value: platformLabel, mono: true),
          const SizedBox(height: TdSpace.s16),
          const TdHairline(),
          const SizedBox(height: TdSpace.s16),
          TdConfirmationCode(code: code),
          const SizedBox(height: TdSpace.s8),
          Text(
            'Check that your phone shows the same code.',
            style: type.secondary.copyWith(color: tokens.muted),
          ),
          const SizedBox(height: TdSpace.s16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TdButton(
                label: 'Decline',
                onPressed: busy ? null : onDecline,
                variant: TdButtonVariant.tertiary,
                disabledReason: busyReason,
              ),
              const SizedBox(width: TdSpace.s8),
              TdButton(
                label: 'Approve',
                onPressed: busy ? null : onApprove,
                variant: TdButtonVariant.primary,
                disabledReason: busyReason,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.mono,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: type.secondary.copyWith(color: tokens.muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: (mono ? type.meta : type.secondary).copyWith(
              color: tokens.text,
            ),
          ),
        ),
      ],
    );
  }
}
