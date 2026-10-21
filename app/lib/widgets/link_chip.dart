import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'pressable.dart';

/// A link inside a chat message or note: mono domain in a 1 px bordered chip.
/// No favicons and no previews — TwinDrop never fetches the URL (docs/13 §6,
/// MSG-008). The browser opens only on an explicit tap.
class TdLinkChip extends StatelessWidget {
  const TdLinkChip({
    super.key,
    required this.url,
    this.label,
    this.onTap,
    this.maxWidth,
    this.inverted = false,
  });

  final String url;

  /// Overrides the displayed text; defaults to the URL's domain.
  final String? label;
  final VoidCallback? onTap;
  final double? maxWidth;

  /// Renders dark-on-paper for chips inside my own (inverted) bubbles.
  final bool inverted;

  /// Domain shown in the chip: bare host, no `www.`, no path or query.
  static String domainOf(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host;
    if (host == null || host.isEmpty) return url;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    final text = label ?? domainOf(url);
    final interactive = onTap != null;
    final foreground = inverted ? tokens.onPaper : tokens.text;
    final idleBackground = inverted ? TdPalette.transparent : tokens.surface;
    final activeBackground = inverted
        ? tokens.onPaper.withValues(alpha: 0.10)
        : tokens.raised;
    final idleBorder = inverted
        ? tokens.onPaper.withValues(alpha: 0.35)
        : tokens.hairline;
    final focusBorder = inverted ? tokens.onPaper : tokens.accent;

    final chip = TdPressable(
      onPressed: onTap,
      enabled: interactive,
      semanticLabel: 'Link to $text',
      semanticHint: interactive ? 'Opens in your browser' : null,
      builder: (context, state) {
        return Container(
          constraints: BoxConstraints(maxWidth: maxWidth ?? double.infinity),
          padding: const EdgeInsets.symmetric(
            horizontal: TdSpace.s8,
            vertical: TdSpace.s4,
          ),
          decoration: BoxDecoration(
            color: state.isActive ? activeBackground : idleBackground,
            borderRadius: TdRadius.allSm,
            border: Border.all(
              color: state.focused ? focusBorder : idleBorder,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  text,
                  style: type.meta.copyWith(color: foreground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
    return Align(alignment: Alignment.centerLeft, child: chip);
  }
}
