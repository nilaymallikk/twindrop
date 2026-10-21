import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'link_chip.dart';
import 'pressable.dart';
import 'td_icons.dart';

/// A notepad note card: `surface`, 1 px hairline, radius 10, no shadow; hover
/// `raised`. Title 15/600, body three lines in `textSecondary`, mono meta row,
/// pinned mark top-right (not a stripe, not a fill), and a mono `conflict copy`
/// tag with a 1 px border for conflict copies (docs/13 §6).
class TdNoteCard extends StatelessWidget {
  const TdNoteCard({
    super.key,
    required this.body,
    this.title,
    this.url,
    this.metaLabel,
    this.pinned = false,
    this.conflict = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.onOpenLink,
  });

  final String body;
  final String? title;
  final String? url;
  final String? metaLabel;
  final bool pinned;
  final bool conflict;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;

    return TdPressable(
      onPressed: onTap,
      onLongPress: onLongPress,
      semanticLabel: _semanticLabel,
      semanticHint: onTap == null ? null : 'Opens the note',
      builder: (context, state) {
        final borderColor = selected
            ? tokens.accent
            : state.focused
                ? tokens.accent
                : tokens.hairline;
        return Container(
          padding: const EdgeInsets.all(TdSpace.s12),
          decoration: BoxDecoration(
            color: state.hovered || selected ? tokens.raised : tokens.surface,
            borderRadius: TdRadius.allMd,
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (title != null && title!.trim().isNotEmpty) ...<
                            Widget>[
                          Text(
                            title!,
                            style: type.cardTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: TdSpace.s4),
                        ],
                        Text(
                          body,
                          style: type.body.copyWith(
                            color: tokens.textSecondary,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (pinned)
                    Padding(
                      padding: const EdgeInsets.only(left: TdSpace.s8),
                      child: TdIcon(
                        TdIcons.pin,
                        size: TdIconSizes.sm,
                        color: tokens.muted,
                        semanticLabel: 'Pinned',
                      ),
                    ),
                ],
              ),
              if (url != null) ...<Widget>[
                const SizedBox(height: TdSpace.s8),
                TdPressable(
                  onPressed: onOpenLink,
                  enabled: onOpenLink != null,
                  semanticLabel: 'Link to ${TdLinkChip.domainOf(url!)}',
                  semanticHint: onOpenLink == null
                      ? null
                      : 'Opens in your browser',
                  builder: (context, chipState) {
                    return Text(
                      TdLinkChip.domainOf(url!),
                      style: type.meta.copyWith(
                        color: chipState.isActive
                            ? tokens.text
                            : tokens.textSecondary,
                        decoration: TextDecoration.underline,
                        decorationColor: tokens.hairline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ],
              const SizedBox(height: TdSpace.s8),
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      metaLabel ?? '',
                      style: type.meta.copyWith(color: tokens.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (conflict) ...<Widget>[
                    const SizedBox(width: TdSpace.s8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: TdSpace.s4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: TdRadius.allXs,
                        border: Border.all(color: tokens.hairline, width: 1),
                      ),
                      child: Text(
                        'conflict copy',
                        style: type.meta.copyWith(color: tokens.muted),
                        maxLines: 1,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String get _semanticLabel {
    final parts = <String>[
      if (title != null && title!.trim().isNotEmpty) title!,
      body,
      if (pinned) 'Pinned',
      if (conflict) 'Conflict copy',
    ];
    return parts.join('. ');
  }
}
