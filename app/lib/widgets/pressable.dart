import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Interaction state handed to a [TdPressable] builder.
@immutable
class TdInteractionState {
  const TdInteractionState({
    this.hovered = false,
    this.focused = false,
    this.pressed = false,
  });

  final bool hovered;
  final bool focused;
  final bool pressed;

  bool get isActive => hovered || focused;
}

/// Shared keyboard/mouse/focus plumbing for custom interactive surfaces
/// (list rows, link chips, message bubbles). Keyboard activation works with
/// Enter and Space; focus and hover are exposed to the builder so controls can
/// render visible focus rings (docs/13 §3, accessibility rules).
class TdPressable extends StatefulWidget {
  const TdPressable({
    super.key,
    required this.onPressed,
    required this.builder,
    this.onLongPress,
    this.enabled = true,
    this.semanticLabel,
    this.semanticHint,
    this.semanticButton = true,
    this.excludeSemantics = false,
    this.focusNode,
  });

  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final TdPressableBuilder builder;
  final bool enabled;
  final String? semanticLabel;
  final String? semanticHint;
  final bool semanticButton;
  final bool excludeSemantics;
  final FocusNode? focusNode;

  @override
  State<TdPressable> createState() => _TdPressableState();
}

typedef TdPressableBuilder = Widget Function(
  BuildContext context,
  TdInteractionState state,
);

class _TdPressableState extends State<TdPressable> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  bool get _enabled => widget.enabled && widget.onPressed != null;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final state = TdInteractionState(
      hovered: _hovered,
      focused: _focused,
      pressed: _pressed,
    );

    Widget interactive = FocusableActionDetector(
      enabled: _enabled,
      focusNode: widget.focusNode,
      mouseCursor:
          _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) {
        if (_focused != value) setState(() => _focused = value);
      },
      onShowHoverHighlight: (value) {
        if (_hovered != value) setState(() => _hovered = value);
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            if (_enabled) widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onLongPress: widget.onLongPress,
        onTapDown: _enabled ? (_) => _setPressed(true) : null,
        onTapUp: _enabled ? (_) => _setPressed(false) : null,
        onTapCancel: _enabled ? () => _setPressed(false) : null,
        child: widget.builder(context, state),
      ),
    );

    if (widget.excludeSemantics) return interactive;
    return Semantics(
      button: widget.semanticButton,
      enabled: _enabled,
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      child: interactive,
    );
  }
}
