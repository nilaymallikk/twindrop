import 'package:flutter/widgets.dart';
import 'package:twindrop_core/models/enums.dart';

import '../theme/context_ext.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';

/// Visual tone of a connection state. Status never relies on colour alone: the
/// dot is always accompanied by a text label (DES-005).
enum TdStatusTone { ok, warn, neutral }

/// The user-facing label for a connection state (docs/02 §1, PAIR-006).
String tdConnectionLabel(ConnectionStatus status) {
  switch (status) {
    case ConnectionStatus.connected:
      return 'Connected';
    case ConnectionStatus.syncing:
      return 'Syncing';
    case ConnectionStatus.connecting:
      return 'Connecting';
    case ConnectionStatus.pairing:
      return 'Pairing';
    case ConnectionStatus.searching:
      return 'Searching';
    case ConnectionStatus.offline:
      return 'Offline';
    case ConnectionStatus.unpaired:
      return 'Not paired';
    case ConnectionStatus.paused:
      return 'Paused';
    case ConnectionStatus.removed:
      return 'Removed';
  }
}

/// Tone for a connection state: `ok`/`warn` colour the dot only; offline and
/// unpaired are hollow rings in `muted` (docs/13 §6 "Status").
TdStatusTone tdConnectionTone(ConnectionStatus status) {
  switch (status) {
    case ConnectionStatus.connected:
    case ConnectionStatus.syncing:
      return TdStatusTone.ok;
    case ConnectionStatus.connecting:
    case ConnectionStatus.pairing:
    case ConnectionStatus.searching:
      return TdStatusTone.warn;
    case ConnectionStatus.offline:
    case ConnectionStatus.unpaired:
    case ConnectionStatus.paused:
    case ConnectionStatus.removed:
      return TdStatusTone.neutral;
  }
}

/// A single status dot (also used for unread markers).
class TdDot extends StatelessWidget {
  const TdDot({super.key, this.color, this.hollow = false, this.size = 8});

  final Color? color;

  /// Hollow ring for "not connected" states.
  final bool hollow;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final resolved = color ?? tokens.muted;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hollow ? null : resolved,
          border: hollow ? Border.all(color: resolved, width: 1.5) : null,
        ),
      ),
    );
  }
}

/// Unread marker. Accent is allowed for the unread dot (docs/13 §1).
class TdUnreadDot extends StatelessWidget {
  const TdUnreadDot({super.key, this.size = 6});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Unread',
      child: TdDot(color: context.td.accent, size: size),
    );
  }
}

/// Dot + label status indicator.
class TdStatus extends StatelessWidget {
  const TdStatus({
    super.key,
    required this.status,
    this.showLabel = true,
    this.dotSize = 8,
    this.mono = false,
  });

  final ConnectionStatus status;
  final bool showLabel;
  final double dotSize;

  /// Device/status rows use mono meta text; app chrome uses sans.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final tone = tdConnectionTone(status);
    final color = switch (tone) {
      TdStatusTone.ok => tokens.ok,
      TdStatusTone.warn => tokens.warn,
      TdStatusTone.neutral => tokens.muted,
    };
    final label = tdConnectionLabel(status);
    final style = mono
        ? context.tdType.meta.copyWith(color: tokens.muted)
        : context.tdType.secondary;
    if (!showLabel) {
      return Semantics(
        label: label,
        child: TdDot(color: color, size: dotSize),
      );
    }
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TdDot(
            color: color,
            size: dotSize,
            hollow: tone == TdStatusTone.neutral,
          ),
          const SizedBox(width: TdSpace.s8),
          Text(label, style: style, maxLines: 1),
        ],
      ),
    );
  }
}

/// Wraps content so it can be used in a dark-on-light context swap (used by the
/// QR tile). Kept here because it needs the type scale.
class TdMonoLabel extends StatelessWidget {
  const TdMonoLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final TdType type = context.tdType;
    return Text(
      text,
      style: type.meta.copyWith(color: color ?? context.td.muted),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
