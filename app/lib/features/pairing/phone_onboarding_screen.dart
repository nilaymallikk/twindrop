import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/confirmation_code.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/primitives.dart';
import '../../widgets/states.dart';
import '../../widgets/td_icons.dart';
import '../models.dart';

/// Phone onboarding (PAIR-001..PAIR-005, docs/02 §1).
///
/// Every step asks for exactly one thing and always offers a way out, so the
/// user is never trapped in a permission wall. The screen is pure
/// presentation: it renders [PhoneOnboardingData] and reports intent through
/// callbacks.
class PhoneOnboardingScreen extends StatefulWidget {
  const PhoneOnboardingScreen({
    super.key,
    required this.data,
    required this.onStartScan,
    required this.onSubmitQr,
    required this.onManualEntry,
    required this.onConfirmFingerprint,
    required this.onSubmitManual,
    required this.onPermissionDecided,
    required this.onSkip,
    required this.onCancel,
    required this.onDone,
  });

  final PhoneOnboardingData data;
  final VoidCallback onStartScan;
  final ValueChanged<String> onSubmitQr;
  final VoidCallback onManualEntry;
  final ValueChanged<String> onConfirmFingerprint;
  final void Function(String hostPort, String code) onSubmitManual;
  final ValueChanged<PermissionStepState> onPermissionDecided;
  final ValueChanged<PhonePermission> onSkip;
  final VoidCallback onCancel;
  final Future<void> Function() onDone;

  @override
  State<PhoneOnboardingScreen> createState() => _PhoneOnboardingScreenState();
}

class _PhoneOnboardingScreenState extends State<PhoneOnboardingScreen> {
  final TextEditingController _address = TextEditingController();
  final TextEditingController _code = TextEditingController();
  bool _addressPrefilled = false;

  @override
  void didUpdateWidget(PhoneOnboardingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prefill = widget.data.manualAddress;
    if (prefill != null && prefill.isNotEmpty && !_addressPrefilled) {
      _address.text = prefill;
      _addressPrefilled = true;
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return ColoredBox(
      color: tokens.bg,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(TdSpace.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (widget.data.stage) {
      case PhoneOnboardingStage.welcome:
        return _welcome(context);
      case PhoneOnboardingStage.scan:
        return _scan(context);
      case PhoneOnboardingStage.manualEntry:
        return _manualEntry(context);
      case PhoneOnboardingStage.fingerprintConfirm:
        return _fingerprintConfirm(context);
      case PhoneOnboardingStage.confirmCode:
        return _confirmCode(context);
      case PhoneOnboardingStage.waitingApproval:
        return _waitingApproval(context);
      case PhoneOnboardingStage.permissions:
        return _permissions(context);
      case PhoneOnboardingStage.connected:
        return _connected(context);
      case PhoneOnboardingStage.error:
        return _error(context);
    }
  }

  Widget _title(BuildContext context, String text, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(text, style: context.tdType.screen),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: TdSpace.s8),
          Text(subtitle, style: context.tdType.secondary),
        ],
        const SizedBox(height: TdSpace.s24),
      ],
    );
  }

  Widget _welcome(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          context,
          'Set up TwinDrop',
          subtitle:
              'Pair this phone with the desktop. Both devices must be on '
              'the same Wi-Fi.',
        ),
        TdButton(
          label: 'Scan the code on the desktop',
          icon: TdIcons.scan,
          expand: true,
          onPressed: widget.onStartScan,
        ),
        const SizedBox(height: TdSpace.s12),
        TdButton(
          label: 'Enter the address manually',
          variant: TdButtonVariant.tertiary,
          expand: true,
          onPressed: widget.onManualEntry,
        ),
      ],
    );
  }

  Widget _scan(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(context, 'Scan the pairing code'),
        _QrScanner(onSubmitQr: widget.onSubmitQr),
        const SizedBox(height: TdSpace.s16),
        TdButton(
          label: 'Enter it manually instead',
          variant: TdButtonVariant.secondary,
          expand: true,
          onPressed: widget.onManualEntry,
        ),
        const SizedBox(height: TdSpace.s8),
        TdButton(
          label: 'Back',
          variant: TdButtonVariant.tertiary,
          expand: true,
          onPressed: widget.onCancel,
        ),
      ],
    );
  }

  Widget _manualEntry(BuildContext context) {
    final error = widget.data.errorMessage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          context,
          'Enter the address',
          subtitle:
              'Type the address shown on the desktop, then the pairing '
              'code next to it.',
        ),
        TdSectionLabel('Address'),
        const SizedBox(height: TdSpace.s8),
        _Field(controller: _address, hint: '192.168.1.23:47321', mono: true),
        const SizedBox(height: TdSpace.s16),
        TdSectionLabel('Pairing code'),
        const SizedBox(height: TdSpace.s8),
        _Field(controller: _code, hint: '4-character code', mono: true),
        if (error != null) ...<Widget>[
          const SizedBox(height: TdSpace.s12),
          TdErrorState(message: error),
        ],
        const SizedBox(height: TdSpace.s24),
        TdButton(
          label: 'Continue',
          expand: true,
          onPressed: widget.data.busy
              ? null
              : () => widget.onSubmitManual(
                  _address.text.trim(),
                  _code.text.trim(),
                ),
        ),
        const SizedBox(height: TdSpace.s8),
        TdButton(
          label: 'Back',
          variant: TdButtonVariant.tertiary,
          expand: true,
          onPressed: widget.onCancel,
        ),
      ],
    );
  }

  Widget _fingerprintConfirm(BuildContext context) {
    final fingerprint = widget.data.fingerprint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          context,
          'Check the security code',
          subtitle:
              'Compare this with the code on the desktop. They must '
              'match exactly.',
        ),
        if (fingerprint == null)
          TdErrorState(message: 'The desktop did not send a fingerprint.')
        else
          Center(
            child: TdConfirmationCode(code: fingerprint, label: 'Desktop code'),
          ),
        const SizedBox(height: TdSpace.s24),
        TdButton(
          label: 'They match',
          expand: true,
          onPressed: fingerprint == null
              ? null
              : () => widget.onConfirmFingerprint(fingerprint),
        ),
        const SizedBox(height: TdSpace.s8),
        TdButton(
          label: 'They do not match',
          variant: TdButtonVariant.secondary,
          expand: true,
          onPressed: widget.onCancel,
        ),
      ],
    );
  }

  Widget _confirmCode(BuildContext context) {
    final code = widget.data.confirmationCode ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          context,
          'Confirm the code',
          subtitle:
              'The desktop shows the same code. Approve only if they '
              'match.',
        ),
        Center(child: TdConfirmationCode(code: code)),
        const SizedBox(height: TdSpace.s24),
        const TdLoadingState(label: 'Waiting for the desktop', lines: 0),
      ],
    );
  }

  Widget _waitingApproval(BuildContext context) {
    final desktop = widget.data.desktopName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          context,
          desktop == null ? 'Waiting for the desktop' : 'Waiting for $desktop',
          subtitle: 'Approve the request on the desktop to finish pairing.',
        ),
        const TdLoadingState(label: 'Waiting for approval', lines: 0),
      ],
    );
  }

  Widget _permissions(BuildContext context) {
    final steps = widget.data.permissions;
    final pending = steps.where((s) => !s.decided).toList();
    final current = pending.isEmpty ? null : pending.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          context,
          'Two small permissions',
          subtitle:
              'TwinDrop works without them; they only make delivery '
              'faster and more reliable. You can skip any step.',
        ),
        if (current == null)
          const TdLoadingState(label: 'Finishing', lines: 0)
        else ...<Widget>[
          _PermissionCard(
            step: current,
            onAllow: () => widget.onPermissionDecided(
              PermissionStepState(
                permission: current.permission,
                granted: true,
              ),
            ),
            onSkip: () => widget.onSkip(current.permission),
          ),
          const SizedBox(height: TdSpace.s16),
          TdSectionLabel(
            '${steps.where((s) => s.decided).length} of ${steps.length} done',
          ),
        ],
      ],
    );
  }

  Widget _connected(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(
          context,
          'You are paired',
          subtitle:
              'Messages and links now sync between this phone and '
              '${widget.data.desktopName ?? 'the desktop'}.',
        ),
        TdButton(
          label: 'Open TwinDrop',
          expand: true,
          onPressed: () => widget.onDone(),
        ),
      ],
    );
  }

  Widget _error(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _title(context, 'Pairing did not work'),
        TdErrorState(
          message: widget.data.errorMessage ?? 'Pairing failed.',
          actionLabel: widget.data.errorActionLabel ?? 'Try again',
          onAction: widget.onStartScan,
          secondaryActionLabel: 'Enter the address manually',
          onSecondaryAction: widget.onManualEntry,
        ),
      ],
    );
  }
}

/// Live camera preview that reports the first QR payload it sees.
class _QrScanner extends StatefulWidget {
  const _QrScanner({required this.onSubmitQr});

  final ValueChanged<String> onSubmitQr;

  @override
  State<_QrScanner> createState() => _QrScannerState();
}

class _QrScannerState extends State<_QrScanner> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return ClipRRect(
      borderRadius: TdRadius.allLg,
      child: AspectRatio(
        aspectRatio: 1,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => ColoredBox(
                color: tokens.raised,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(TdSpace.s16),
                    child: Text(
                      'The camera could not start. Enter the address '
                      'manually instead.',
                      textAlign: TextAlign.center,
                      style: context.tdType.secondary,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: TdSpace.s8,
              top: TdSpace.s8,
              child: TdIconButton(
                icon: TdIcons.flashlight,
                label: 'Toggle the torch',
                onPressed: _controller.toggleTorch,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;
      _handled = true;
      widget.onSubmitQr(value);
      return;
    }
  }
}

/// One permission request with an explicit Allow and Skip.
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.step,
    required this.onAllow,
    required this.onSkip,
  });

  final PermissionStepState step;
  final VoidCallback onAllow;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return Container(
      padding: const EdgeInsets.all(TdSpace.s16),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border.all(color: tokens.hairline),
        borderRadius: TdRadius.allMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(step.permission.title, style: context.tdType.cardTitle),
          const SizedBox(height: TdSpace.s8),
          Text(step.permission.description, style: context.tdType.secondary),
          const SizedBox(height: TdSpace.s16),
          TdButton(label: 'Allow', onPressed: onAllow),
          const SizedBox(height: TdSpace.s8),
          TdButton(
            label: 'Skip',
            variant: TdButtonVariant.tertiary,
            onPressed: onSkip,
          ),
        ],
      ),
    );
  }
}

/// Plain text field styled with the design tokens.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.mono = false,
  });

  final TextEditingController controller;
  final String hint;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return TextField(
      controller: controller,
      style: mono ? context.tdType.mono : context.tdType.body,
      cursorColor: tokens.accent,
      inputFormatters: <TextInputFormatter>[
        if (mono) FilteringTextInputFormatter.deny(RegExp(r'\s')),
      ],
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: (mono ? context.tdType.mono : context.tdType.body).copyWith(
          color: tokens.muted,
        ),
        filled: true,
        fillColor: tokens.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: TdSpace.s12,
          vertical: TdSpace.s12,
        ),
        border: OutlineInputBorder(
          borderRadius: TdRadius.allSm,
          borderSide: BorderSide(color: tokens.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: TdRadius.allSm,
          borderSide: BorderSide(color: tokens.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: TdRadius.allSm,
          borderSide: BorderSide(color: tokens.accent),
        ),
      ),
    );
  }
}
