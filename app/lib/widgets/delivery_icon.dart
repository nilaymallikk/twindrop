import 'package:flutter/widgets.dart';
import 'package:twindrop_core/models/enums.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import 'td_icons.dart';

/// Delivery state of an outgoing message: clock (queued), single check (sent),
/// double check (delivered). Delivered is never shown without a peer ack
/// (MSG-006); this widget only renders the state it is given.
class TdDeliveryIcon extends StatelessWidget {
  const TdDeliveryIcon({super.key, required this.state, this.color});

  final DeliveryState state;
  final Color? color;

  static String labelFor(DeliveryState state) {
    switch (state) {
      case DeliveryState.queued:
        return 'Queued';
      case DeliveryState.sent:
        return 'Sent';
      case DeliveryState.delivered:
        return 'Delivered';
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final (icon, resolved) = switch (state) {
      DeliveryState.queued => (TdIcons.clock, tokens.muted),
      DeliveryState.sent => (TdIcons.check, tokens.muted),
      DeliveryState.delivered => (TdIcons.checkCheck, tokens.textSecondary),
    };
    return TdIcon(
      icon,
      size: TdIconSizes.delivery,
      color: color ?? resolved,
      semanticLabel: labelFor(state),
    );
  }
}
