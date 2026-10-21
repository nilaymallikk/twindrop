import 'package:flutter/material.dart';
import 'package:twindrop_core/models/enums.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../../widgets/logo_mark.dart';
import '../../widgets/pressable.dart';
import '../../widgets/primitives.dart';
import '../../widgets/status.dart';
import '../../widgets/td_icons.dart';
import '../models.dart';

/// The app frame shared by phone and desktop.
///
/// Phone: bottom navigation with Chat · Notepad · Settings (24 px outline
/// icons). Desktop: left sidebar with the same three sections, the product
/// mark, and a status chip. The content is supplied by the host as [child], so
/// the shell owns only navigation and chrome.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.section,
    required this.onSectionChanged,
    required this.child,
    required this.status,
    this.peerName,
    this.showSidebar = false,
    this.unreadChat = 0,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSectionChanged;
  final Widget child;
  final ConnectionStatus status;
  final String? peerName;

  /// Desktop layout: render the sidebar instead of the bottom bar. The host
  /// decides (platform + window size); the shell falls back to the bottom bar
  /// when the window is narrow.
  final bool showSidebar;

  /// Unread indicator on the Chat entry.
  final int unreadChat;

  static String labelFor(AppSection section) {
    switch (section) {
      case AppSection.chat:
        return 'Chat';
      case AppSection.notepad:
        return 'Notepad';
      case AppSection.settings:
        return 'Settings';
    }
  }

  static TdIconData iconFor(AppSection section) {
    switch (section) {
      case AppSection.chat:
        return TdIcons.chat;
      case AppSection.notepad:
        return TdIcons.note;
      case AppSection.settings:
        return TdIcons.settings;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            showSidebar && constraints.maxWidth >= TdBreakpoint.phoneMax;
        if (wide) {
          return ColoredBox(
            color: tokens.bg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SizedBox(
                  width: 208,
                  child: _Sidebar(
                    section: section,
                    onSectionChanged: onSectionChanged,
                    status: status,
                    peerName: peerName,
                    unreadChat: unreadChat,
                  ),
                ),
                const TdHairline(vertical: true),
                Expanded(child: child),
              ],
            ),
          );
        }
        final bottomInset = MediaQuery.paddingOf(context).bottom;
        return ColoredBox(
          color: tokens.bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(child: child),
              const TdHairline(),
              Padding(
                padding: EdgeInsets.only(bottom: bottomInset),
                child: _BottomNav(
                  section: section,
                  onSectionChanged: onSectionChanged,
                  unreadChat: unreadChat,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.section,
    required this.onSectionChanged,
    required this.status,
    required this.peerName,
    required this.unreadChat,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSectionChanged;
  final ConnectionStatus status;
  final String? peerName;
  final int unreadChat;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return ColoredBox(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              TdSpace.s16,
              TdSpace.s16,
              TdSpace.s16,
              TdSpace.s12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const TdLogoMark(size: 20, semanticLabel: 'TwinDrop'),
                    const SizedBox(width: TdSpace.s8),
                    Expanded(
                      child: Text(
                        'TwinDrop',
                        style: type.label.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: TdSpace.s12),
                TdStatus(status: status),
                if (peerName != null) ...<Widget>[
                  const SizedBox(height: TdSpace.s4),
                  Text(
                    peerName!,
                    style: type.meta.copyWith(color: tokens.muted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const TdHairline(),
          const SizedBox(height: TdSpace.s8),
          for (final item in AppSection.values)
            _SidebarItem(
              section: item,
              selected: item == section,
              unread: item == AppSection.chat ? unreadChat : 0,
              onPressed: () => onSectionChanged(item),
            ),
          const Spacer(),
          if (peerName == null)
            Padding(
              padding: const EdgeInsets.all(TdSpace.s16),
              child: Text(
                'Connect a device to start.',
                style: type.meta.copyWith(color: tokens.muted),
              ),
            ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.section,
    required this.selected,
    required this.unread,
    required this.onPressed,
  });

  final AppSection section;
  final bool selected;
  final int unread;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return TdPressable(
      onPressed: onPressed,
      semanticLabel: AppShell.labelFor(section),
      semanticHint: unread > 0 ? '$unread unread' : null,
      builder: (context, state) {
        final active = selected || state.hovered;
        return Container(
          constraints: const BoxConstraints(minHeight: 40),
          color: active ? tokens.raised : tokens.bg,
          padding: const EdgeInsets.symmetric(horizontal: TdSpace.s16),
          child: Row(
            children: <Widget>[
              TdIcon(
                AppShell.iconFor(section),
                size: TdIconSizes.md,
                color: selected ? tokens.text : tokens.muted,
              ),
              const SizedBox(width: TdSpace.s12),
              Expanded(
                child: Text(
                  AppShell.labelFor(section),
                  style: type.label.copyWith(
                    color: selected ? tokens.text : tokens.textSecondary,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (unread > 0) TdUnreadDot(),
            ],
          ),
        );
      },
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.section,
    required this.onSectionChanged,
    required this.unreadChat,
  });

  final AppSection section;
  final ValueChanged<AppSection> onSectionChanged;
  final int unreadChat;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final type = context.tdType;
    return Row(
      children: <Widget>[
        for (final item in AppSection.values)
          Expanded(
            child: TdPressable(
              onPressed: () => onSectionChanged(item),
              semanticLabel: AppShell.labelFor(item),
              semanticHint: item == AppSection.chat && unreadChat > 0
                  ? '$unreadChat unread'
                  : null,
              builder: (context, state) {
                final selected = item == section;
                final color = selected ? tokens.text : tokens.muted;
                return Container(
                  constraints: const BoxConstraints(minHeight: 56),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: selected ? tokens.paper : TdPalette.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          TdIcon(
                            AppShell.iconFor(item),
                            size: TdIconSizes.lg,
                            color: color,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppShell.labelFor(item),
                            style: type.secondary.copyWith(
                              color: color,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                      if (item == AppSection.chat && unreadChat > 0)
                        Positioned(top: 8, right: 24, child: TdUnreadDot()),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
