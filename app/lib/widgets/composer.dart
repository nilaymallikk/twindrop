import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'pressable.dart';
import 'search_field.dart';
import 'td_icons.dart';

/// Message composer: `surface`, 1 px hairline, radius 10; focus is a 1 px
/// accent border (no glow). The send button is the only accent-filled control
/// in chat and stays disabled until there is text (docs/13 §6).
///
/// Enter sends, Shift+Enter inserts a newline. On phone the field grows to
/// five lines; the send affordance remains a 48 dp target.
class TdComposer extends StatefulWidget {
  const TdComposer({
    super.key,
    required this.onSend,
    this.controller,
    this.focusNode,
    this.hint = 'Message',
    this.showKeyboardHint = false,
    this.enabled = true,
    this.disabledReason,
    this.pasteSuggestion,
    this.autofocus = false,
    this.onEscape,
  });

  final ValueChanged<String> onSend;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String hint;
  final bool showKeyboardHint;
  final bool enabled;
  final String? disabledReason;

  /// Text the app found on the clipboard. Tapping the paste chip inserts it;
  /// TwinDrop never reads the clipboard on its own.
  final String? pasteSuggestion;
  final bool autofocus;

  /// Escape hides the desktop popup; wired by the host.
  final VoidCallback? onEscape;

  @override
  State<TdComposer> createState() => _TdComposerState();
}

class _TdComposerState extends State<TdComposer> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _focused = false;

  bool get _hasText => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _ownsFocusNode = widget.focusNode == null;
    _controller.addListener(_onChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (mounted && _focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _focusNode.removeListener(_onFocusChanged);
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  void _pasteSuggestion() {
    final suggestion = widget.pasteSuggestion;
    if (suggestion == null) return;
    _controller.value = TextEditingValue(
      text: suggestion,
      selection: TextSelection.collapsed(offset: suggestion.length),
    );
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    final enabled = widget.enabled;
    final canSend = enabled && _hasText;

    final field = Container(
      constraints: BoxConstraints(minHeight: context.tdControlHeight),
      padding: const EdgeInsets.symmetric(horizontal: TdSpace.s12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: TdRadius.allMd,
        border: Border.all(
          color: _focused ? tokens.accent : tokens.hairline,
          width: 1,
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        enabled: enabled,
        autofocus: widget.autofocus,
        minLines: 1,
        maxLines: 5,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        style: context.tdBody,
        cursorColor: tokens.accent,
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          hintText: widget.hint,
          hintStyle: context.tdBody.copyWith(color: tokens.muted),
          contentPadding: const EdgeInsets.symmetric(vertical: TdSpace.s12),
        ),
      ),
    );

    final sendButton = TdPressable(
      onPressed: canSend ? _send : null,
      enabled: canSend,
      semanticLabel: 'Send',
      semanticHint: widget.enabled ? null : widget.disabledReason,
      builder: (context, state) {
        final background = canSend
            ? (state.isActive
                ? Color.alphaBlend(
                    tokens.onAccent.withValues(alpha: 0.12), tokens.accent)
                : tokens.accent)
            : tokens.raised;
        return Container(
          width: context.tdControlHeight,
          height: context.tdControlHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: TdRadius.allSm,
            border: Border.all(
              color: state.focused && canSend
                  ? tokens.onAccent
                  : TdPalette.transparent,
              width: 1,
            ),
          ),
          child: TdIcon(
            TdIcons.send,
            size: TdIconSizes.md,
            color: canSend ? tokens.onAccent : tokens.muted,
          ),
        );
      },
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter): _send,
        if (widget.onEscape != null)
          const SingleActivator(LogicalKeyboardKey.escape): widget.onEscape!,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (widget.pasteSuggestion != null) ...<Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: TdPressable(
                onPressed: _pasteSuggestion,
                semanticLabel: 'Paste from clipboard',
                builder: (context, state) => Container(
                  margin: const EdgeInsets.only(bottom: TdSpace.s8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: TdSpace.s8,
                    vertical: TdSpace.s4,
                  ),
                  decoration: BoxDecoration(
                    color: state.isActive ? tokens.raised : tokens.surface,
                    borderRadius: TdRadius.allSm,
                    border: Border.all(
                      color: state.focused ? tokens.accent : tokens.hairline,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TdIcon(
                        TdIcons.clipboard,
                        size: TdIconSizes.sm,
                        color: tokens.muted,
                      ),
                      const SizedBox(width: TdSpace.s8),
                      Flexible(
                        child: Text(
                          'Paste ${_shorten(widget.pasteSuggestion!)}',
                          style: type.meta.copyWith(color: tokens.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(child: field),
              const SizedBox(width: TdSpace.s8),
              sendButton,
            ],
          ),
          if (!enabled && widget.disabledReason != null) ...<Widget>[
            const SizedBox(height: TdSpace.s8),
            Text(
              widget.disabledReason!,
              style: type.meta.copyWith(color: tokens.muted),
            ),
          ],
          if (widget.showKeyboardHint) ...<Widget>[
            const SizedBox(height: TdSpace.s8),
            const TdKeyboardHint(
              parts: <String>['Enter to send', 'Shift+Enter for new line'],
            ),
          ],
        ],
      ),
    );
  }

  static String _shorten(String value) {
    final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= 32) return singleLine;
    return '${singleLine.substring(0, 31)}…';
  }
}
