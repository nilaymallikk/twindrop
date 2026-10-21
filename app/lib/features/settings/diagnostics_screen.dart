import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/states.dart';

/// Diagnostics screen (docs/02 §Diagnostics, docs/09).
///
/// Shows only what the user can act on: the addresses the desktop serves, the
/// pinned certificate, the last known peer address, and buttons that retry the
/// connection or set a manual address. Nothing here logs secrets.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    super.key,
    required this.localAddresses,
    required this.mdnsSummary,
    required this.onTestConnection,
    required this.onManualAddress,
    required this.onRetry,
    this.peerLabel,
    this.peerLastAddress,
    this.pinState,
    this.firewallHint,
    this.serverPort = 0,
  });

  final List<String> localAddresses;
  final String? peerLabel;
  final String? peerLastAddress;
  final String mdnsSummary;
  final String? pinState;
  final Future<String?> Function() onTestConnection;
  final Future<void> Function(String hostPort) onManualAddress;
  final Future<void> Function() onRetry;
  final String? firewallHint;
  final int serverPort;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  final TextEditingController _manual = TextEditingController();
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _manual.text = widget.peerLastAddress ?? '';
  }

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(
        backgroundColor: tokens.bg,
        foregroundColor: tokens.text,
        elevation: 0,
        title: const Text('Diagnostics'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(TdSpace.s16),
        children: <Widget>[
          TdScreenHeader(
            title: 'Diagnostics',
            subtitle: Text(
              'Everything here stays on this device.',
              style: context.tdType.meta,
            ),
          ),
          const SizedBox(height: TdSpace.s16),
          _group(
            context,
            'This device',
            <Widget>[
              _row('Addresses', widget.localAddresses.isEmpty
                  ? 'None found'
                  : widget.localAddresses.join(', '), mono: true),
              if (widget.serverPort > 0)
                _row('Server port', '${widget.serverPort}', mono: true),
              if (widget.pinState != null)
                _row('Certificate', widget.pinState!, mono: true),
              _row('Discovery', widget.mdnsSummary),
            ],
          ),
          const SizedBox(height: TdSpace.s16),
          _group(
            context,
            'Desktop',
            <Widget>[
              _row('Paired device', widget.peerLabel ?? 'Not paired'),
              _row(
                'Last known address',
                widget.peerLastAddress ?? 'Unknown',
                mono: true,
              ),
            ],
          ),
          const SizedBox(height: TdSpace.s16),
          _group(
            context,
            'Connection',
            <Widget>[
              TdButton(
                label: 'Test the connection',
                variant: TdButtonVariant.secondary,
                expand: true,
                onPressed: _testing ? null : _test,
              ),
              if (_testResult != null) ...<Widget>[
                const SizedBox(height: TdSpace.s12),
                TdNotice(message: _testResult!, tone: TdNoticeTone.neutral),
              ],
              const SizedBox(height: TdSpace.s12),
              TdButton(
                label: 'Retry now',
                variant: TdButtonVariant.secondary,
                expand: true,
                onPressed: widget.onRetry,
              ),
            ],
          ),
          const SizedBox(height: TdSpace.s16),
          _group(
            context,
            'Manual address',
            <Widget>[
              Text(
                'Use this when discovery cannot find the desktop.',
                style: context.tdType.meta,
              ),
              const SizedBox(height: TdSpace.s8),
              _manualField(context),
              const SizedBox(height: TdSpace.s12),
              TdButton(
                label: 'Use this address',
                variant: TdButtonVariant.secondary,
                expand: true,
                onPressed: _manual.text.trim().isEmpty
                    ? null
                    : () => widget.onManualAddress(_manual.text.trim()),
              ),
            ],
          ),
          if (widget.firewallHint != null) ...<Widget>[
            const SizedBox(height: TdSpace.s16),
            _group(
              context,
              'If the phone cannot connect',
              <Widget>[
                Text(
                  'Some firewalls block the port. Allow it on the desktop:',
                  style: context.tdType.meta,
                ),
                const SizedBox(height: TdSpace.s8),
                SelectableText(
                  widget.firewallHint!,
                  style: context.tdType.mono,
                ),
              ],
            ),
          ],
          const SizedBox(height: TdSpace.s32),
        ],
      ),
    );
  }

  Widget _group(BuildContext context, String title, List<Widget> children) {
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
          TdSectionLabel(title),
          const SizedBox(height: TdSpace.s12),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TdSpace.s8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 140, child: Text(label, style: context.tdType.meta)),
          Expanded(
            child: Text(
              value,
              style: mono ? context.tdType.mono : context.tdType.body,
            ),
          ),
        ],
      ),
    );
  }

  Widget _manualField(BuildContext context) {
    final tokens = context.td;
    return TextField(
      controller: _manual,
      style: context.tdType.mono,
      cursorColor: tokens.accent,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: '192.168.1.23:47321',
        hintStyle: context.tdType.mono.copyWith(color: tokens.muted),
        filled: true,
        fillColor: tokens.raised,
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

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final result = await widget.onTestConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = result ?? 'The connection test finished.';
    });
  }
}
