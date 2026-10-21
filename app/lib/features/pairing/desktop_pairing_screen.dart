import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../../widgets/approval_card.dart';
import '../../widgets/buttons.dart';
import '../../widgets/confirmation_code.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/primitives.dart';
import '../../widgets/qr_tile.dart';
import '../../widgets/states.dart';
import '../models.dart';

/// Desktop pairing surface (PAIR-001..PAIR-005).
///
/// Pure presentation: the screen renders exactly what [DesktopPairingData]
/// says and never starts a session, approves a device or talks to the network
/// itself. Every action is a callback the host wires up.
class DesktopPairingScreen extends StatelessWidget {
  const DesktopPairingScreen({
    super.key,
    required this.data,
    required this.onStart,
    required this.onCancel,
    required this.onApprove,
    required this.onReject,
    this.onRetry,
  });

  final DesktopPairingData data;
  final VoidCallback onStart;
  final VoidCallback onCancel;
  final ValueChanged<String> onApprove;
  final ValueChanged<String> onReject;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          'Pair a phone',
          style: context.tdType.screen,
        ),
        const SizedBox(height: TdSpace.s4),
        Text(
          'Open TwinDrop on the phone and scan this code, or type the address '
          'below. Both devices must be on the same Wi-Fi.',
          style: context.tdType.secondary,
        ),
        const SizedBox(height: TdSpace.s24),
        _body(context),
      ],
    );
  }

  Widget _body(BuildContext context) {
    switch (data.stage) {
      case DesktopPairingStage.idle:
        return _idle(context);
      case DesktopPairingStage.waitingForPhone:
        return _waiting(context);
      case DesktopPairingStage.approval:
        return _approval(context);
      case DesktopPairingStage.connected:
        return _connected(context);
      case DesktopPairingStage.error:
        return _error(context);
    }
  }

  Widget _idle(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TdEmptyState(
          message: data.errorMessage ?? 'No pairing session is running.',
          actionLabel: 'Create a code',
          onAction: onStart,
          compact: true,
        ),
      ],
    );
  }

  Widget _waiting(BuildContext context) {
    final payload = data.qrPayload;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (payload != null)
          Center(
            child: TdQrTile(
              data: payload,
              size: 208,
              semanticLabel: 'Pairing QR code',
            ),
          )
        else
          TdEmptyState(
            message: 'Waiting for the phone to connect.',
            compact: true,
          ),
        if (data.manualAddress != null) ...<Widget>[
          const SizedBox(height: TdSpace.s20),
          _DetailRow(
            label: 'Address',
            value: data.manualAddress!,
            mono: true,
          ),
        ],
        if (data.fingerprint != null) ...<Widget>[
          const SizedBox(height: TdSpace.s8),
          _DetailRow(
            label: 'Security code',
            value: data.fingerprint!,
            mono: true,
          ),
        ],
        if (data.expiryLabel != null) ...<Widget>[
          const SizedBox(height: TdSpace.s16),
          TdSectionLabel('Expires in ${data.expiryLabel}'),
        ],
        const SizedBox(height: TdSpace.s16),
        TdButton(
          label: 'Cancel',
          variant: TdButtonVariant.secondary,
          onPressed: data.busy ? null : onCancel,
        ),
      ],
    );
  }

  Widget _approval(BuildContext context) {
    final requestId = data.requestId;
    final code = data.confirmationCode ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TdApprovalCard(
          deviceName: data.requestDeviceName ?? 'Unknown device',
          platformLabel: data.requestPlatform ?? 'Unknown platform',
          code: code,
          busy: data.busy,
          onApprove: requestId == null ? () {} : () => onApprove(requestId),
          onDecline: requestId == null ? () {} : () => onReject(requestId),
        ),
        if (code.isNotEmpty) ...<Widget>[
          const SizedBox(height: TdSpace.s16),
          Center(child: TdConfirmationCode(code: code)),
        ],
        const SizedBox(height: TdSpace.s12),
        Text(
          'The phone shows the same code. Only approve if they match.',
          style: context.tdType.meta,
        ),
        if (requestId == null) ...<Widget>[
          const SizedBox(height: TdSpace.s12),
          TdErrorState(
            message: 'The approval request expired. Start a new pairing '
                'session.',
            actionLabel: 'Start over',
            onAction: onRetry,
          ),
        ],
      ],
    );
  }

  Widget _connected(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TdNotice(
          message: 'Paired with ${data.connectedDeviceName ?? 'the phone'}. '
              'Messages now sync both ways.',
          tone: TdNoticeTone.neutral,
        ),
        const SizedBox(height: TdSpace.s16),
        TdButton(
          label: 'Done',
          variant: TdButtonVariant.secondary,
          onPressed: onCancel,
        ),
      ],
    );
  }

  Widget _error(BuildContext context) {
    return TdErrorState(
      message: data.errorMessage ?? 'Pairing failed.',
      actionLabel: 'Try again',
      onAction: onRetry ?? onStart,
      secondaryActionLabel: 'Cancel',
      onSecondaryAction: onCancel,
    );
  }
}

/// Label/value row used by the pairing screen for mono technical values.
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: 112,
          child: Text(label, style: context.tdType.meta),
        ),
        Expanded(
          child: Text(
            value,
            style: mono ? context.tdType.mono : context.tdType.body,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
