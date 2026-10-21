import 'package:flutter/material.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'pressable.dart';
import 'primitives.dart';
import 'toggle.dart';
import 'td_icons.dart';

/// One settings/diagnostics row. `label` plus optional secondary line and a
/// value or trailing control; rows with [onTap] are keyboard-operable.
class TdSettingsRow extends StatelessWidget {
  const TdSettingsRow({
    super.key,
    required this.label,
    this.description,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
    this.enabled = true,
    this.disabledReason,
    this.monoValue = false,
  });

  final String label;
  final String? description;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  final bool enabled;
  final String? disabledReason;

  /// Diagnostics values are mono; settings values are sans.
  final bool monoValue;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    final interactive = onTap != null && enabled;

    Widget content(TdInteractionState state) => Container(
      constraints: const BoxConstraints(minHeight: 44),
      color: state.isActive ? tokens.raised : tokens.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: TdSpace.s12,
        vertical: TdSpace.s8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  label,
                  style: type.label.copyWith(
                    color: !enabled
                        ? tokens.muted
                        : destructive
                        ? tokens.error
                        : tokens.text,
                  ),
                ),
                if (description != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    description!,
                    style: type.secondary.copyWith(color: tokens.muted),
                  ),
                ],
              ],
            ),
          ),
          if (value != null) ...<Widget>[
            const SizedBox(width: TdSpace.s12),
            Flexible(
              child: Text(
                value!,
                style: (monoValue ? type.meta : type.secondary).copyWith(
                  color: tokens.muted,
                ),
                textAlign: TextAlign.right,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (trailing != null) ...<Widget>[
            const SizedBox(width: TdSpace.s12),
            trailing!,
          ],
          if (interactive) ...<Widget>[
            const SizedBox(width: TdSpace.s8),
            TdIcon(
              TdIcons.chevronRight,
              size: TdIconSizes.sm,
              color: tokens.muted,
            ),
          ],
        ],
      ),
    );

    final row = TdPressable(
      onPressed: onTap,
      enabled: interactive,
      semanticLabel: label,
      semanticHint: enabled ? null : disabledReason,
      builder: (context, state) => content(state),
    );

    final hint = enabled ? null : disabledReason;
    if (hint != null) return Tooltip(message: hint, child: row);
    return row;
  }
}

/// A settings row whose trailing control is a [TdToggle].
class TdToggleRow extends StatelessWidget {
  const TdToggleRow({
    super.key,
    required this.label,
    this.description,
    required this.value,
    required this.onChanged,
    this.disabledReason,
  });

  final String label;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    return TdSettingsRow(
      label: label,
      description: description,
      enabled: onChanged != null,
      disabledReason: disabledReason,
      trailing: TdToggle(
        value: value,
        onChanged: onChanged,
        semanticLabel: label,
        disabledReason: disabledReason,
      ),
    );
  }
}

/// A single-select choice row (appearance, default share action, sort). Uses a
/// custom radio: hairline ring, `paper` dot when selected.
class TdChoiceRow extends StatelessWidget {
  const TdChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.description,
  });

  final String label;
  final String? description;
  final bool selected;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return TdPressable(
      onPressed: onSelected,
      semanticLabel: label,
      semanticHint: selected ? 'Selected' : null,
      builder: (context, state) {
        return Container(
          constraints: const BoxConstraints(minHeight: 44),
          color: state.isActive ? tokens.raised : tokens.surface,
          padding: const EdgeInsets.symmetric(
            horizontal: TdSpace.s12,
            vertical: TdSpace.s8,
          ),
          child: Row(
            children: <Widget>[
              SizedBox.square(
                dimension: 16,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? tokens.text : tokens.hairline,
                      width: 1,
                    ),
                  ),
                  child: selected
                      ? Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: tokens.paper,
                            ),
                          ),
                        )
                      : null,
                ),
              ),
              const SizedBox(width: TdSpace.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(label, style: type.label),
                    if (description != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        description!,
                        style: type.secondary.copyWith(color: tokens.muted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A read-only mono value line used in Diagnostics.
class TdValueLine extends StatelessWidget {
  const TdValueLine({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TdSpace.s12,
        vertical: TdSpace.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: type.secondary.copyWith(color: tokens.muted)),
          const SizedBox(height: 2),
          SelectableText(value, style: type.mono.copyWith(color: tokens.text)),
        ],
      ),
    );
  }
}

/// Group divider inside settings groups; re-exported for convenience.
Widget tdGroupDividers(List<Widget> rows) {
  final result = <Widget>[];
  for (var i = 0; i < rows.length; i++) {
    if (i > 0) result.add(const TdHairline());
    result.add(rows[i]);
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: result,
  );
}
