import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'buttons.dart';
import 'primitives.dart';
import 'status.dart';
import 'td_icons.dart';

/// Loading state: plain placeholder lines, never a shimmer skeleton
/// (docs/13 §7). Announce "Loading" to screen readers.
class TdLoadingState extends StatelessWidget {
  const TdLoadingState({super.key, this.label = 'Loading', this.lines = 3});

  final String label;
  final int lines;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final widths = <double>[0.7, 0.85, 0.55, 0.65, 0.4];
    return Semantics(
      label: label,
      child: Padding(
        padding: const EdgeInsets.all(TdSpace.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (var i = 0; i < lines; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: TdSpace.s12),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: widths[i % widths.length],
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: tokens.raised,
                      borderRadius: TdRadius.allXs,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Inline error/notice: a plain 1 px bordered row with an outline alert icon.
/// Actions are optional; the copy is passed in so screens use docs/02 wording.
class TdNotice extends StatelessWidget {
  const TdNotice({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.tone = TdNoticeTone.error,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final TdNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    final color = switch (tone) {
      TdNoticeTone.error => tokens.error,
      TdNoticeTone.warn => tokens.warn,
      TdNoticeTone.neutral => tokens.muted,
    };
    final icon = switch (tone) {
      TdNoticeTone.error => TdIcons.alert,
      TdNoticeTone.warn => TdIcons.wifi,
      TdNoticeTone.neutral => TdIcons.shield,
    };
    return Container(
      padding: const EdgeInsets.all(TdSpace.s12),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: TdRadius.allMd,
        border: Border.all(color: tokens.hairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: TdIcon(icon, size: TdIconSizes.sm, color: color),
              ),
              const SizedBox(width: TdSpace.s8),
              Expanded(
                child: Text(
                  message,
                  style: type.secondary.copyWith(color: tokens.textSecondary),
                ),
              ),
            ],
          ),
          if ((actionLabel != null && onAction != null) ||
              (secondaryActionLabel != null &&
                  onSecondaryAction != null)) ...<Widget>[
            const SizedBox(height: TdSpace.s8),
            Wrap(
              spacing: TdSpace.s8,
              runSpacing: TdSpace.s4,
              children: <Widget>[
                if (actionLabel != null && onAction != null)
                  TdButton(
                    label: actionLabel!,
                    onPressed: onAction,
                    variant: TdButtonVariant.secondary,
                  ),
                if (secondaryActionLabel != null && onSecondaryAction != null)
                  TdButton(
                    label: secondaryActionLabel!,
                    onPressed: onSecondaryAction,
                    variant: TdButtonVariant.tertiary,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

enum TdNoticeTone { error, warn, neutral }

/// Full-pane error state. The message should be the exact actionable copy from
/// docs/02 so every failure says what to do next.
class TdErrorState extends StatelessWidget {
  const TdErrorState({
    super.key,
    required this.message,
    this.actionLabel = 'Retry',
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.tone = TdNoticeTone.error,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final TdNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.all(TdSpace.s16),
        child: TdNotice(
          message: message,
          actionLabel: actionLabel,
          onAction: onAction,
          secondaryActionLabel: secondaryActionLabel,
          onSecondaryAction: onSecondaryAction,
          tone: tone,
        ),
      ),
    );
  }
}

/// Offline banner shown above the chat timeline: hollow status dot, a plain
/// sentence, and Retry / Troubleshoot actions (docs/02 §2).
class TdOfflineBanner extends StatelessWidget {
  const TdOfflineBanner({
    super.key,
    required this.message,
    this.onRetry,
    this.onTroubleshoot,
    this.retryLabel = 'Retry',
    this.troubleshootLabel = 'Troubleshoot',
  });

  final String message;
  final VoidCallback? onRetry;
  final VoidCallback? onTroubleshoot;
  final String retryLabel;
  final String troubleshootLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TdSpace.s12,
        vertical: TdSpace.s8,
      ),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.hairline, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          const TdDot(hollow: true, size: 8),
          const SizedBox(width: TdSpace.s8),
          Expanded(
            child: Text(
              message,
              style: type.secondary.copyWith(color: tokens.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: TdSpace.s8),
          if (onRetry != null)
            TdInlineAction(label: retryLabel, onPressed: onRetry),
          if (onTroubleshoot != null) ...<Widget>[
            const SizedBox(width: TdSpace.s4),
            TdInlineAction(
              label: troubleshootLabel,
              onPressed: onTroubleshoot,
              mono: false,
            ),
          ],
        ],
      ),
    );
  }
}

/// Section label: mono 12 muted, used above grouped settings rows. Small mono
/// tags are the only all-lowercase/all-caps labels (docs/13 §2).
class TdSectionLabel extends StatelessWidget {
  const TdSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TdSpace.s8),
      child: Text(
        label,
        style: context.tdType.meta.copyWith(color: context.td.muted),
      ),
    );
  }
}

/// A hairline-ruled group of rows, used by Settings and Diagnostics.
class TdGroup extends StatelessWidget {
  const TdGroup({super.key, required this.children, this.padding});

  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: TdRadius.allMd,
        border: Border.all(color: tokens.hairline, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// A 1 px hairline between rows of a [TdGroup].
class TdGroupDivider extends StatelessWidget {
  const TdGroupDivider({super.key});

  @override
  Widget build(BuildContext context) => const TdHairline();
}
