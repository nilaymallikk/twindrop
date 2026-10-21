import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'pressable.dart';
import 'td_icons.dart';

/// Search field: `surface`, 1 px hairline, radius 10, accent focus border (no
/// glow). Clear action appears only when there is text.
class TdSearchField extends StatefulWidget {
  const TdSearchField({
    super.key,
    this.controller,
    this.onChanged,
    this.hint = 'Search notes',
    this.autofocus = false,
  });

  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String hint;
  final bool autofocus;

  @override
  State<TdSearchField> createState() => _TdSearchFieldState();
}

class _TdSearchFieldState extends State<TdSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final hasText = _controller.text.isNotEmpty;

    return Container(
      constraints: BoxConstraints(minHeight: context.tdControlHeight),
      padding: const EdgeInsets.symmetric(horizontal: TdSpace.s8),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: TdRadius.allMd,
        border: Border.all(color: tokens.hairline, width: 1),
      ),
      child: Row(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TdSpace.s4),
            child: TdIcon(
              TdIcons.search,
              size: TdIconSizes.sm,
              color: tokens.muted,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: widget.onChanged,
              autofocus: widget.autofocus,
              style: context.tdBody,
              cursorColor: tokens.accent,
              decoration: InputDecoration(
                isDense: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: widget.hint,
                hintStyle: context.tdBody.copyWith(color: tokens.muted),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: TdSpace.s8,
                  vertical: TdSpace.s12,
                ),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => widget.onChanged?.call(value),
            ),
          ),
          if (hasText)
            TdPressable(
              onPressed: () {
                _controller.clear();
                widget.onChanged?.call('');
              },
              semanticLabel: 'Clear search',
              builder: (context, state) => Padding(
                padding: const EdgeInsets.all(TdSpace.s4),
                child: TdIcon(
                  TdIcons.close,
                  size: TdIconSizes.sm,
                  color: state.isActive ? tokens.text : tokens.muted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Keyboard shortcut hint: mono 12 muted, used under the desktop popup composer
/// (`Enter to send · Shift+Enter for new line`).
class TdKeyboardHint extends StatelessWidget {
  const TdKeyboardHint({super.key, required this.parts});

  /// Human-readable key hints joined with `·`.
  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return Text(
      parts.join(' · '),
      style: type.meta.copyWith(color: tokens.muted),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Thin wrapper that turns a physical Enter key into "send" while Shift+Enter
/// inserts a newline. Used by the composer and by screens that need shortcut
/// handling without changing text field behaviour elsewhere.
class TdSendOnEnter extends StatelessWidget {
  const TdSendOnEnter({
    super.key,
    required this.onSend,
    required this.child,
  });

  final VoidCallback onSend;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey != LogicalKeyboardKey.enter) {
          return KeyEventResult.ignored;
        }
        final pressed = HardwareKeyboard.instance;
        if (pressed.isShiftPressed) return KeyEventResult.ignored;
        onSend();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}
