import 'package:flutter/widgets.dart';
import 'package:twindrop_core/models/enums.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'delivery_icon.dart';
import 'link_chip.dart';

/// One chat message.
///
/// My messages: `paper` bubble with `onPaper` text. Other device: `raised`
/// bubble with a 1 px hairline in `text` colour. Radius 10 with a 3 px corner
/// nearest the sender. Meta line (device · time) in mono 12 `muted`, delivery
/// icons 14 px (docs/13 §6).
class TdChatBubble extends StatelessWidget {
  const TdChatBubble({
    super.key,
    required this.text,
    required this.mine,
    required this.deviceLabel,
    required this.timeLabel,
    this.delivery,
    this.linkUrl,
    this.onOpenLink,
    this.onMenuRequested,
    this.selected = false,
    this.selectionMode = false,
    this.animateIn = false,
  });

  final String text;
  final bool mine;
  final String deviceLabel;
  final String timeLabel;

  /// Outgoing only: queued/sent/delivered. Null on received messages.
  final DeliveryState? delivery;
  final String? linkUrl;
  final VoidCallback? onOpenLink;

  /// Long-press / right-click opens the message menu (Copy · Save to Notepad ·
  /// Delete · Select). The pointer position lets desktop anchor a popup menu.
  final ValueChanged<Offset>? onMenuRequested;
  final bool selected;
  final bool selectionMode;

  /// New messages fade in over 140 ms with a 4 px rise; disabled when the OS
  /// asks to reduce motion (docs/13 §7).
  final bool animateIn;

  BorderRadius get _radius {
    const r = Radius.circular(TdRadius.md);
    const near = Radius.circular(3);
    return mine
        ? const BorderRadius.only(
            topLeft: r,
            topRight: r,
            bottomLeft: r,
            bottomRight: near,
          )
        : const BorderRadius.only(
            topLeft: r,
            topRight: r,
            bottomLeft: near,
            bottomRight: r,
          );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    final bodyStyle = context.tdBody.copyWith(
      color: mine ? tokens.onPaper : tokens.text,
    );

    final bubble = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: TdSpace.s12,
        vertical: TdSpace.s8,
      ),
      decoration: BoxDecoration(
        color: mine ? tokens.paper : tokens.raised,
        borderRadius: _radius,
        border: Border.all(
          color: selected
              ? tokens.accent
              : mine
              ? tokens.paper
              : tokens.hairline,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(text, style: bodyStyle),
          if (linkUrl != null) ...<Widget>[
            const SizedBox(height: TdSpace.s8),
            TdLinkChip(url: linkUrl!, onTap: onOpenLink, inverted: mine),
          ],
        ],
      ),
    );

    final meta = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            '$deviceLabel · $timeLabel',
            style: type.meta.copyWith(color: tokens.muted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (mine && delivery != null) ...<Widget>[
          const SizedBox(width: TdSpace.s4),
          TdDeliveryIcon(state: delivery!),
        ],
      ],
    );

    final content = LayoutBuilder(
      builder: (context, constraints) {
        final maxBubble = constraints.maxWidth * 0.78;
        final align = mine ? Alignment.centerRight : Alignment.centerLeft;
        final cross = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;

        Widget result = Column(
          crossAxisAlignment: cross,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Align(
              alignment: align,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxBubble),
                child: bubble,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: TdSpace.s4),
              child: Align(alignment: align, child: meta),
            ),
          ],
        );

        if (animateIn && !context.tdReduceMotion) {
          result = TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: TdMotion.message,
            curve: TdMotion.curve,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, TdMotion.messageRise * (1 - value)),
                child: child,
              ),
            ),
            child: result,
          );
        }
        return result;
      },
    );

    final labelled = Semantics(
      selected: selectionMode ? selected : null,
      label:
          '${mine ? 'You' : deviceLabel}, $timeLabel. $text'
          '${delivery != null ? '. ${TdDeliveryIcon.labelFor(delivery!)}' : ''}',
      excludeSemantics: true,
      child: content,
    );

    if (onMenuRequested == null) return labelled;
    return GestureDetector(
      onLongPressStart: (details) => onMenuRequested!(details.globalPosition),
      onSecondaryTapUp: (details) => onMenuRequested!(details.globalPosition),
      child: labelled,
    );
  }
}
