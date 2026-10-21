import 'package:flutter/material.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/chat_bubble.dart';
import '../../widgets/date_separator.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/td_icons.dart';
import '../format.dart';
import '../models.dart';

/// Scrollable chat timeline with date separators, quiet auto-scroll and
/// jump-to-latest. Pure view: all actions come in through callbacks.
class ChatTimeline extends StatefulWidget {
  const ChatTimeline({
    super.key,
    required this.entries,
    this.onOpenLink,
    this.onMenuRequested,
    this.selectionMode = false,
    this.selectedIds = const <String>{},
    this.onToggleSelected,
    this.emptyMessage = 'No messages yet. Type below to send the first one.',
    this.showJumpButton = true,
  });

  final List<ChatEntry> entries;
  final ValueChanged<ChatEntry>? onOpenLink;
  final void Function(ChatEntry entry, Offset globalPosition)? onMenuRequested;
  final bool selectionMode;
  final Set<String> selectedIds;
  final ValueChanged<ChatEntry>? onToggleSelected;
  final String emptyMessage;
  final bool showJumpButton;

  @override
  State<ChatTimeline> createState() => _ChatTimelineState();
}

class _ChatTimelineState extends State<ChatTimeline> {
  final ScrollController _controller = ScrollController();
  bool _showJump = false;
  Set<String> _previousIds = const <String>{};

  /// Length of the entry list before the last update. Used to tell a genuinely
  /// new message (animate it in) from a re-render of the same list.
  int? _previousCount;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom(animate: false));
  }

  @override
  void didUpdateWidget(ChatTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entries.length != oldWidget.entries.length) {
      _previousIds = oldWidget.entries.map((entry) => entry.id).toSet();
      _previousCount = oldWidget.entries.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        final distance =
            _controller.position.maxScrollExtent - _controller.offset;
        final nearBottom = distance < 160;
        if (nearBottom || oldWidget.entries.isEmpty) {
          _jumpToBottom(animate: true);
        } else {
          setState(() => _showJump = true);
        }
      });
    }
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final distance = _controller.position.maxScrollExtent - _controller.offset;
    final next = distance > 80;
    if (next != _showJump) setState(() => _showJump = next);
  }

  void _jumpToBottom({required bool animate}) {
    if (!_controller.hasClients) return;
    final target = _controller.position.maxScrollExtent;
    if (animate && !context.tdReduceMotion) {
      _controller.animateTo(
        target,
        duration: TdMotion.sheet,
        curve: TdMotion.curve,
      );
    } else {
      _controller.jumpTo(target);
    }
    if (_showJump) setState(() => _showJump = false);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: TdEmptyState(message: widget.emptyMessage),
      );
    }

    final rows = _buildRows(widget.entries);
    final lastEntryId = widget.entries.last.id;
    final oldIds = _previousIds;

    return Stack(
      children: <Widget>[
        ListView.builder(
          controller: _controller,
          padding: const EdgeInsets.symmetric(
            horizontal: TdSpace.s16,
            vertical: TdSpace.s12,
          ),
          itemCount: rows.length,
          itemBuilder: (context, index) {
            final row = rows[index];
            if (row.separatorFor != null) {
              return TdDateSeparator(
                key: ValueKey<String>('separator-${row.separatorFor}'),
                label: tdDateSeparatorLabel(row.separatorFor!),
              );
            }
            final entry = row.entry!;
            final selected = widget.selectedIds.contains(entry.id);
            final animateIn = entry.id == lastEntryId &&
                (_previousCount ?? 0) < widget.entries.length &&
                !oldIds.contains(entry.id);
            Widget bubble = Padding(
              padding: const EdgeInsets.only(bottom: TdSpace.s12),
              child: TdChatBubble(
                text: entry.text,
                mine: entry.mine,
                deviceLabel: entry.label,
                timeLabel: tdClockLabel(entry.createdAt),
                delivery: entry.mine ? entry.delivery : null,
                linkUrl: entry.url,
                onOpenLink: widget.onOpenLink == null
                    ? null
                    : () => widget.onOpenLink!(entry),
                selected: selected,
                selectionMode: widget.selectionMode,
                animateIn: animateIn,
                onMenuRequested: widget.selectionMode ||
                        widget.onMenuRequested == null
                    ? null
                    : (position) => widget.onMenuRequested!(entry, position),
              ),
            );
            if (widget.selectionMode && widget.onToggleSelected != null) {
              bubble = GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => widget.onToggleSelected!(entry),
                child: bubble,
              );
            }
            return KeyedSubtree(
              key: ValueKey<String>('entry-${entry.id}'),
              child: bubble,
            );
          },
        ),
        if (widget.showJumpButton && _showJump)
          Positioned(
            right: TdSpace.s16,
            bottom: TdSpace.s12,
            child: TdButton(
              label: 'Jump to latest',
              icon: TdIcons.arrowDown,
              variant: TdButtonVariant.secondary,
              onPressed: () => _jumpToBottom(animate: true),
            ),
          ),
      ],
    );
  }

  List<_TimelineRow> _buildRows(List<ChatEntry> entries) {
    final rows = <_TimelineRow>[];
    int? lastDayMs;
    for (final entry in entries) {
      final dayMs = _dayStart(entry.createdAt);
      if (lastDayMs != dayMs) {
        rows.add(_TimelineRow.separator(dayMs));
        lastDayMs = dayMs;
      }
      rows.add(_TimelineRow.entry(entry));
    }
    return rows;
  }

  static int _dayStart(int epochMs) {
    final local = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
    return DateTime(local.year, local.month, local.day).millisecondsSinceEpoch;
  }
}

class _TimelineRow {
  const _TimelineRow.separator(this.separatorFor) : entry = null;
  const _TimelineRow.entry(this.entry) : separatorFor = null;

  final int? separatorFor;
  final ChatEntry? entry;
}
