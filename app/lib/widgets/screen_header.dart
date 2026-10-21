import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// Screen header used by every full-screen view: a title, optional leading
/// control and trailing actions, separated by a hairline.
///
/// Uses the screen title style (22/28 semibold) and a 1 px bottom hairline, so
/// screens never need a Material [AppBar].
class TdScreenHeader extends StatelessWidget {
  const TdScreenHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions = const <Widget>[],
    this.subtitle,
    this.showBottomHairline = true,
  });

  final String title;
  final Widget? leading;
  final List<Widget> actions;
  final Widget? subtitle;
  final bool showBottomHairline;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    final minHeight = context.tdIsPhone ? 56.0 : 48.0;
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.symmetric(horizontal: TdSpace.s12),
      decoration: showBottomHairline
          ? BoxDecoration(
              border: Border(
                bottom: BorderSide(color: tokens.hairline, width: 1),
              ),
            )
          : null,
      child: Row(
        children: <Widget>[
          if (leading != null) ...<Widget>[
            leading!,
            const SizedBox(width: TdSpace.s4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: type.screen.copyWith(color: tokens.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                ?subtitle,
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A quiet placeholder panel used by screens that are still loading their data
/// (no spinner chrome, no shimmer).
class TdPlaceholderPanel extends StatelessWidget {
  const TdPlaceholderPanel({super.key, this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return TdSurface(
      color: tokens.surface,
      radius: TdRadius.md,
      height: height,
      child: const SizedBox.expand(),
    );
  }
}
