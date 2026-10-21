import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/primitives.dart';

/// Asks for a category name and awaits the host's create/rename call.
///
/// The dialog stays open and shows the returned message when the host refuses
/// the name, so nothing the user typed is dropped (NOTE-001). Returns the
/// trimmed name, or null when cancelled.
Future<String?> showCategoryNameDialog(
  BuildContext context, {
  required String title,
  required Future<String?> Function(String name) onSubmit,
  String? initialName,
  String confirmLabel = 'Save',
}) {
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: context.td.scrim,
    transitionDuration: context.tdSheet,
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        _CategoryNameDialog(
      title: title,
      initialName: initialName,
      confirmLabel: confirmLabel,
      onSubmit: onSubmit,
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: TdMotion.curve),
        child: child,
      );
    },
  );
}

class _CategoryNameDialog extends StatefulWidget {
  const _CategoryNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.onSubmit,
    this.initialName,
  });

  final String title;
  final String confirmLabel;
  final Future<String?> Function(String name) onSubmit;
  final String? initialName;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName ?? '');
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.onSubmit(name);
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    final busyReason = _busy ? 'Saving…' : null;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(TdSpace.s24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TdSurface(
              color: tokens.raised,
              radius: TdRadius.lg,
              padding: const EdgeInsets.all(TdSpace.s20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(widget.title, style: type.title),
                  const SizedBox(height: TdSpace.s16),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    enabled: !_busy,
                    style: context.tdBody,
                    cursorColor: tokens.accent,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      hintText: 'Category name',
                    ),
                  ),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: TdSpace.s8),
                    Text(
                      _error!,
                      style: type.secondary.copyWith(color: tokens.error),
                    ),
                  ],
                  const SizedBox(height: TdSpace.s20),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: TdSpace.s8,
                    runSpacing: TdSpace.s8,
                    children: <Widget>[
                      TdButton(
                        label: 'Cancel',
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                        disabledReason: busyReason,
                      ),
                      TdButton(
                        label: widget.confirmLabel,
                        variant: TdButtonVariant.primary,
                        onPressed: _busy ? null : _submit,
                        disabledReason: busyReason,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
