import 'package:flutter/widgets.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';

/// The 4-digit pairing confirmation code, large mono digits (32 px, +0.12 em)
/// shown on both devices so the user can compare them (PAIR-003).
class TdConfirmationCode extends StatelessWidget {
  const TdConfirmationCode({
    super.key,
    required this.code,
    this.label = 'Confirmation code',
  });

  final String code;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (label != null)
          Text(
            label!,
            style: type.secondary.copyWith(color: tokens.muted),
          ),
        if (label != null) const SizedBox(height: TdSpace.s4),
        Semantics(
          label: 'Confirmation code $code',
          excludeSemantics: true,
          child: Text(
            code,
            style: type.code.copyWith(color: tokens.text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
