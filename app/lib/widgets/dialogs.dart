import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'buttons.dart';
import 'pressable.dart';
import 'primitives.dart';
import 'td_icons.dart';

/// One action in a [showTdDialog] dialog. The result value is returned by the
/// dialog future when this action is chosen.
@immutable
class TdDialogAction<T> {
  const TdDialogAction({
    required this.label,
    required this.result,
    this.variant = TdButtonVariant.secondary,
  });

  final String label;
  final T result;
  final TdButtonVariant variant;
}

/// One row in a [showTdMenu] / [showTdActionSheet] menu.
@immutable
class TdMenuItem<T> {
  const TdMenuItem({
    required this.label,
    required this.result,
    this.icon,
    this.destructive = false,
    this.enabled = true,
    this.disabledReason,
  });

  final String label;
  final T result;
  final TdIconData? icon;
  final bool destructive;
  final bool enabled;

  /// Shown instead of hiding a control that cannot be used right now.
  final String? disabledReason;
}

/// Modal dialog: `raised` surface, 1 px hairline, 60% black scrim, no blur
/// (docs/13 §3). Fades in; instant when motion is reduced.
Future<T?> showTdDialog<T>(
  BuildContext context, {
  required String title,
  Widget? content,
  required List<TdDialogAction<T>> actions,
  bool dismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: title,
    barrierColor: context.td.scrim,
    transitionDuration: context.tdSheet,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final tokens = dialogContext.td;
      final type = dialogContext.tdType;
      return _DismissOnEscape(
        onDismiss: () => Navigator.of(dialogContext).maybePop(),
        child: SafeArea(
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
                      Text(title, style: type.title),
                      if (content != null) ...<Widget>[
                        const SizedBox(height: TdSpace.s8),
                        DefaultTextStyle.merge(
                          style: type.body.copyWith(
                            color: tokens.textSecondary,
                          ),
                          child: content,
                        ),
                      ],
                      const SizedBox(height: TdSpace.s20),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: TdSpace.s8,
                        runSpacing: TdSpace.s8,
                        children: <Widget>[
                          for (final action in actions)
                            TdButton(
                              label: action.label,
                              variant: action.variant,
                              onPressed: () =>
                                  Navigator.of(dialogContext)
                                      .pop(action.result),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, _, child) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        return child;
      }
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: TdMotion.curve),
        child: child,
      );
    },
  );
}

/// Confirmation dialog used by destructive actions (delete, unpair, clear data).
Future<bool> showTdConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
}) async {
  final result = await showTdDialog<bool>(
    context,
    title: title,
    content: Text(message),
    actions: <TdDialogAction<bool>>[
      TdDialogAction(label: cancelLabel, result: false),
      TdDialogAction(
        label: confirmLabel,
        result: true,
        variant: destructive
            ? TdButtonVariant.destructive
            : TdButtonVariant.primary,
      ),
    ],
  );
  return result ?? false;
}

/// Bottom sheet: `raised`, top radius 14, 1 px top hairline, no drag handle
/// (docs/13 §6). Slides up over 180 ms; instant with reduced motion.
Future<T?> showTdSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: context.td.scrim,
    transitionDuration: context.tdSheet,
    pageBuilder: (sheetContext, animation, secondaryAnimation) {
      final tokens = sheetContext.td;
      final type = sheetContext.tdType;
      final insets = MediaQuery.viewInsetsOf(sheetContext);
      return _DismissOnEscape(
        onDismiss: () => Navigator.of(sheetContext).maybePop(),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: insets.bottom),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  TdSpace.s20,
                  TdSpace.s16,
                  TdSpace.s20,
                  TdSpace.s24,
                ),
                decoration: BoxDecoration(
                  color: tokens.raised,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(TdRadius.lg),
                  ),
                  border: Border(
                    top: BorderSide(color: tokens.hairline, width: 1),
                    left: BorderSide(color: tokens.hairline, width: 1),
                    right: BorderSide(color: tokens.hairline, width: 1),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: type.title),
                      const SizedBox(height: TdSpace.s16),
                      Flexible(child: builder(sheetContext)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondary, child) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        return child;
      }
      final curved = CurvedAnimation(parent: animation, curve: TdMotion.curve);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Action sheet: a title plus a list of text rows. Used for long-press menus on
/// phone.
Future<T?> showTdActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<TdMenuItem<T>> items,
}) {
  return showTdSheet<T>(
    context,
    title: title,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final item in items)
          TdMenuRow<T>(
            item: item,
            onSelected: (value) {
              Navigator.of(sheetContext).pop(value);
            },
          ),
      ],
    ),
  );
}

/// Anchored popup menu for desktop right-click / long-press. No blur, hairline
/// border, `raised` surface.
Future<T?> showTdMenu<T>(
  BuildContext context, {
  required Offset globalPosition,
  required List<TdMenuItem<T>> items,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final overlaySize = overlay?.size ?? MediaQuery.sizeOf(context);
  const itemHeight = 36.0;
  const menuWidth = 220.0;
  final menuHeight = items.length * itemHeight + TdSpace.s8;
  final left = globalPosition.dx.clamp(
    TdSpace.s8,
    (overlaySize.width - menuWidth - TdSpace.s8).clamp(
      TdSpace.s8,
      double.infinity,
    ),
  );
  final top = globalPosition.dy.clamp(
    TdSpace.s8,
    (overlaySize.height - menuHeight - TdSpace.s8).clamp(
      TdSpace.s8,
      double.infinity,
    ),
  );

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Menu',
    barrierColor: context.td.scrim,
    transitionDuration: context.tdFast,
    pageBuilder: (menuContext, animation, secondaryAnimation) {
      final tokens = menuContext.td;
      return Stack(
        children: <Widget>[
          Positioned(
            left: left,
            top: top,
            width: menuWidth,
            child: TdSurface(
              color: tokens.raised,
              radius: TdRadius.sm,
              padding: const EdgeInsets.symmetric(vertical: TdSpace.s4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final item in items)
                    TdMenuRow<T>(
                      item: item,
                      onSelected: (value) {
                        Navigator.of(menuContext).pop(value);
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
    transitionBuilder: (context, animation, _, child) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        return child;
      }
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: TdMotion.curve),
        child: child,
      );
    },
  );
}

/// One menu row: text, optional icon, hover `surface`, focus ring.
class TdMenuRow<T> extends StatelessWidget {
  const TdMenuRow({super.key, required this.item, required this.onSelected});

  final TdMenuItem<T> item;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    final enabled = item.enabled;
    final color = !enabled
        ? tokens.muted
        : item.destructive
        ? tokens.error
        : tokens.text;
    final row = TdPressable(
      onPressed: enabled ? () => onSelected(item.result) : null,
      enabled: enabled,
      semanticLabel: item.label,
      semanticHint: enabled ? null : item.disabledReason,
      builder: (context, state) {
        return Container(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
          padding: const EdgeInsets.symmetric(
            horizontal: TdSpace.s12,
            vertical: TdSpace.s8,
          ),
          color: state.isActive ? tokens.surface : tokens.raised,
          child: Row(
            children: <Widget>[
              if (item.icon != null) ...<Widget>[
                TdIcon(item.icon!, size: TdIconSizes.sm, color: color),
                const SizedBox(width: TdSpace.s8),
              ],
              Expanded(
                child: Text(
                  item.label,
                  style: type.label.copyWith(color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
    if (!enabled && item.disabledReason != null) {
      return Tooltip(message: item.disabledReason!, child: row);
    }
    return row;
  }
}

class _DismissOnEscape extends StatelessWidget {
  const _DismissOnEscape({required this.child, required this.onDismiss});

  final Widget child;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): onDismiss,
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
