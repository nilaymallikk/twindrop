import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// Centered mono date marker with a hairline either side (docs/13 §6 "Chat").
class TdDateSeparator extends StatelessWidget {
  const TdDateSeparator({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: TdSpace.s12),
      child: Row(
        children: <Widget>[
          const Expanded(child: TdHairline()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: TdSpace.s12),
            child: Text(
              label,
              style: type.meta.copyWith(color: tokens.muted),
              maxLines: 1,
            ),
          ),
          const Expanded(child: TdHairline()),
        ],
      ),
    );
  }
}
