import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'td_icons.dart';

/// Button emphasis, matching docs/13 §6: primary = accent fill (send/confirm
/// only), secondary = inverted paper, tertiary = text only, destructive =
/// error text with a dialog confirmation upstream.
enum TdButtonVariant { primary, secondary, tertiary, destructive }

/// A design-system button.
///
/// Every button is keyboard-operable with a visible focus ring. A disabled
/// button must carry [disabledReason] so no control is dead without an
/// explanation (AGENTS rule 7): the reason is exposed as tooltip and semantics
/// hint.
class TdButton extends StatefulWidget {
  const TdButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = TdButtonVariant.secondary,
    this.icon,
    this.expand = false,
    this.disabledReason,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final TdButtonVariant variant;
  final TdIconData? icon;
  final bool expand;
  final String? disabledReason;
  final String? tooltip;

  @override
  State<TdButton> createState() => _TdButtonState();
}

class _TdButtonState extends State<TdButton> {
  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    final enabled = _enabled;

    final background = switch (widget.variant) {
      TdButtonVariant.primary =>
        enabled
            ? (_hovered
                  ? Color.alphaBlend(
                      tokens.onAccent.withValues(alpha: 0.12),
                      tokens.accent,
                    )
                  : tokens.accent)
            : tokens.raised,
      TdButtonVariant.secondary =>
        enabled
            ? (_hovered
                  ? Color.alphaBlend(
                      tokens.onPaper.withValues(alpha: 0.10),
                      tokens.paper,
                    )
                  : tokens.paper)
            : tokens.raised,
      TdButtonVariant.tertiary || TdButtonVariant.destructive =>
        _hovered && enabled ? tokens.raised : TdPalette.transparent,
    };
    final foreground = !enabled
        ? tokens.muted
        : switch (widget.variant) {
            TdButtonVariant.primary => tokens.onAccent,
            TdButtonVariant.secondary => tokens.onPaper,
            TdButtonVariant.tertiary => tokens.text,
            TdButtonVariant.destructive => tokens.error,
          };
    final borderColor = _focused
        ? (widget.variant == TdButtonVariant.primary
              ? tokens.onAccent
              : tokens.accent)
        : (widget.variant == TdButtonVariant.secondary && enabled
              ? tokens.paper
              : TdPalette.transparent);

    final labelStyle = type.label.copyWith(color: foreground);
    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (widget.icon != null) ...<Widget>[
          TdIcon(widget.icon!, size: TdIconSizes.sm, color: foreground),
          const SizedBox(width: TdSpace.s8),
        ],
        Flexible(
          child: Text(
            widget.label,
            style: labelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    Widget button = Container(
      constraints: BoxConstraints(
        minHeight: context.tdControlHeight,
        minWidth: context.tdControlHeight,
      ),
      padding: const EdgeInsets.symmetric(horizontal: TdSpace.s16),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: TdRadius.allSm,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: content,
    );

    button = FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: widget.label,
          hint: enabled ? null : widget.disabledReason,
          child: button,
        ),
      ),
    );

    if (widget.expand) {
      button = SizedBox(width: double.infinity, child: button);
    }
    final tooltip = widget.tooltip ?? (enabled ? null : widget.disabledReason);
    if (tooltip != null) {
      button = Tooltip(message: tooltip, child: button);
    }
    return button;
  }
}

/// A square icon-only button with a required semantic label (accessibility
/// rule: 48 dp targets, labels on icon buttons).
class TdIconButton extends StatefulWidget {
  const TdIconButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = TdIconSizes.md,
    this.selected = false,
    this.color,
    this.tooltip,
    this.disabledReason,
  });

  final TdIconData icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final bool selected;
  final Color? color;
  final String? tooltip;
  final String? disabledReason;

  @override
  State<TdIconButton> createState() => _TdIconButtonState();
}

class _TdIconButtonState extends State<TdIconButton> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final enabled = widget.onPressed != null;
    final foreground = !enabled
        ? tokens.muted
        : (widget.color ??
              (widget.selected ? tokens.text : tokens.textSecondary));
    final side = context.tdControlHeight;
    final background = widget.selected
        ? tokens.raised
        : _hovered && enabled
        ? tokens.raised
        : TdPalette.transparent;

    final button = Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: TdRadius.allSm,
        border: Border.all(
          color: _focused ? tokens.accent : TdPalette.transparent,
          width: 1,
        ),
      ),
      child: TdIcon(widget.icon, size: widget.size, color: foreground),
    );

    Widget interactive = FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: widget.label,
          selected: widget.selected,
          hint: enabled ? null : widget.disabledReason,
          child: button,
        ),
      ),
    );

    final tooltip = widget.tooltip ?? (enabled ? null : widget.disabledReason);
    if (tooltip != null) {
      interactive = Tooltip(message: tooltip, child: interactive);
    }
    return interactive;
  }
}

/// A plain text action (tertiary emphasis) with keyboard support and a focus
/// ring. Used for inline actions in cards, sheets and toasts.
class TdInlineAction extends StatefulWidget {
  const TdInlineAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    this.mono = false,
    this.disabledReason,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool mono;
  final String? disabledReason;

  @override
  State<TdInlineAction> createState() => _TdInlineActionState();
}

class _TdInlineActionState extends State<TdInlineAction> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    final enabled = widget.onPressed != null;
    final color = !enabled
        ? tokens.muted
        : widget.destructive
        ? tokens.error
        : tokens.accent;
    final style = (widget.mono ? type.meta : type.label).copyWith(
      color: color,
      decoration: _hovered && enabled
          ? TextDecoration.underline
          : TextDecoration.none,
      decorationColor: color,
    );

    final action = Container(
      constraints: BoxConstraints(minHeight: 32, minWidth: 32),
      padding: const EdgeInsets.symmetric(
        horizontal: TdSpace.s4,
        vertical: TdSpace.s4,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: TdRadius.allXs,
        border: Border.all(
          color: _focused ? tokens.accent : TdPalette.transparent,
          width: 1,
        ),
      ),
      child: Text(widget.label, style: style, maxLines: 1),
    );

    final interactive = FocusableActionDetector(
      enabled: enabled,
      mouseCursor: enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onShowFocusHighlight: (value) => setState(() => _focused = value),
      onShowHoverHighlight: (value) => setState(() => _hovered = value),
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Semantics(
          button: true,
          enabled: enabled,
          label: widget.label,
          hint: enabled ? null : widget.disabledReason,
          child: action,
        ),
      ),
    );
    if (!enabled && widget.disabledReason != null) {
      return Tooltip(message: widget.disabledReason!, child: interactive);
    }
    return interactive;
  }
}
