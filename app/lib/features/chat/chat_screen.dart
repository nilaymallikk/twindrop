import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twindrop_core/models/enums.dart';

import '../../theme/context_ext.dart';
import '../../theme/tokens.dart';
import '../../widgets/buttons.dart';
import '../../widgets/composer.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/primitives.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/states.dart';
import '../../widgets/status.dart';
import '../../widgets/td_icons.dart';
import '../models.dart';
import 'chat_timeline.dart';

/// What the long-press / right-click menu can do with a message.
enum _ChatMenuAction { copy, save, delete }

/// The chat view shared by the phone, the desktop window and the tray popup.
///
/// Pure view: every action is a callback, so the same widget renders history,
/// the offline banner, loading/error states and the composer without owning
/// state. Delivery icons come from [ChatEntry.delivery] and are never invented.
class ChatScreen extends StatelessWidget {
  const ChatScreen({
    super.key,
    required this.entries,
    required this.status,
    this.peerName,
    this.isLoading = false,
    this.errorMessage,
    this.onRetry,
    this.onTroubleshoot,
    required this.onSend,
    required this.onSaveToNotepad,
    this.onDelete,
    this.onCopy,
    this.onOpenLink,
    this.onShowNotepad,
    this.onShowSettings,
    this.isPopup = false,
    this.onClose,
    this.composerFocusNode,
    this.showKeyboardHint = false,
    this.pasteSuggestion,
    this.hasMore = false,
    this.onLoadOlder,
    this.onOpenApp,
  });

  final List<ChatEntry> entries;
  final ConnectionStatus status;
  final String? peerName;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onTroubleshoot;
  final ValueChanged<String> onSend;
  final ValueChanged<ChatEntry> onSaveToNotepad;
  final ValueChanged<ChatEntry>? onDelete;
  final ValueChanged<ChatEntry>? onCopy;
  final ValueChanged<String>? onOpenLink;
  final VoidCallback? onShowNotepad;
  final VoidCallback? onShowSettings;

  /// Tray popup chrome: compact header, Escape hides the popup.
  final bool isPopup;
  final VoidCallback? onClose;

  /// Host-owned focus node so the host can focus the input from a shortcut.
  final FocusNode? composerFocusNode;
  final bool showKeyboardHint;
  final String? pasteSuggestion;
  final bool hasMore;
  final VoidCallback? onLoadOlder;

  /// Popup only: opens the full window. Null in the full window.
  final VoidCallback? onOpenApp;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    final offline = _offlineMessage(status);

    return ColoredBox(
      color: tokens.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _header(context),
          if (offline != null)
            TdOfflineBanner(
              message: offline,
              onRetry: onRetry,
              onTroubleshoot: onTroubleshoot,
            ),
          if (hasMore)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: TdSpace.s4),
              child: Center(
                child: TdInlineAction(
                  label: 'Load older messages',
                  onPressed: onLoadOlder,
                  disabledReason: onLoadOlder == null
                      ? 'Older messages are still loading.'
                      : null,
                ),
              ),
            ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: TdContentWidth.chat,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(child: _body(context)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        TdSpace.s12,
                        TdSpace.s8,
                        TdSpace.s12,
                        TdSpace.s12,
                      ),
                      child: TdComposer(
                        onSend: onSend,
                        focusNode: composerFocusNode,
                        showKeyboardHint: showKeyboardHint || isPopup,
                        pasteSuggestion: pasteSuggestion,
                        onEscape: isPopup ? onClose : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (errorMessage != null) {
      return TdErrorState(message: errorMessage!, onAction: onRetry);
    }
    if (isLoading) return const TdLoadingState(label: 'Loading messages');
    return ChatTimeline(
      entries: entries,
      onOpenLink: onOpenLink == null ? null : _openLink,
      onMenuRequested: (entry, position) =>
          _showMessageMenu(context, entry, position),
      emptyMessage: 'No messages yet. Type below to send the first one.',
    );
  }

  void _openLink(ChatEntry entry) {
    final url = entry.url;
    if (url != null) onOpenLink?.call(url);
  }

  Widget _header(BuildContext context) {
    if (isPopup) {
      return TdScreenHeader(
        title: peerName ?? 'Chat',
        subtitle: TdStatus(status: status, mono: true, dotSize: 6),
        actions: <Widget>[
          if (onOpenApp != null)
            TdIconButton(
              icon: TdIcons.openExternal,
              label: 'Open full app',
              tooltip: 'Open full app',
              onPressed: onOpenApp,
            ),
          if (onClose != null)
            TdIconButton(
              icon: TdIcons.close,
              label: 'Close',
              tooltip: 'Close',
              onPressed: onClose,
            ),
        ],
      );
    }
    return TdScreenHeader(
      title: peerName ?? 'Chat',
      subtitle: TdStatus(status: status, mono: true),
      actions: <Widget>[
        if (onShowNotepad != null)
          TdIconButton(
            icon: TdIcons.note,
            label: 'Notepad',
            onPressed: onShowNotepad,
          ),
        if (onShowSettings != null)
          TdIconButton(
            icon: TdIcons.settings,
            label: 'Settings',
            onPressed: onShowSettings,
          ),
      ],
    );
  }

  Future<void> _showMessageMenu(
    BuildContext context,
    ChatEntry entry,
    Offset globalPosition,
  ) async {
    final items = <TdMenuItem<_ChatMenuAction>>[
      const TdMenuItem<_ChatMenuAction>(
        label: 'Copy',
        result: _ChatMenuAction.copy,
        icon: TdIcons.copy,
      ),
      const TdMenuItem<_ChatMenuAction>(
        label: 'Save to Notepad',
        result: _ChatMenuAction.save,
        icon: TdIcons.note,
      ),
      if (onDelete != null)
        const TdMenuItem<_ChatMenuAction>(
          label: 'Delete',
          result: _ChatMenuAction.delete,
          icon: TdIcons.trash,
          destructive: true,
        ),
    ];
    final action = await showTdMenu<_ChatMenuAction>(
      context,
      globalPosition: globalPosition,
      items: items,
    );
    switch (action) {
      case _ChatMenuAction.copy:
        final text = entry.text.isNotEmpty ? entry.text : (entry.url ?? '');
        if (text.isEmpty) return;
        await Clipboard.setData(ClipboardData(text: text));
        onCopy?.call(entry);
      case _ChatMenuAction.save:
        onSaveToNotepad(entry);
      case _ChatMenuAction.delete:
        onDelete?.call(entry);
      case null:
        return;
    }
  }

  static String? _offlineMessage(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.offline:
      case ConnectionStatus.searching:
        return "Can't reach your desktop. Is it on the same Wi-Fi and "
            'running TwinDrop?';
      case ConnectionStatus.unpaired:
        return 'Not paired yet. Pair with your desktop to start.';
      case ConnectionStatus.removed:
        return 'This phone was removed from the desktop.';
      case ConnectionStatus.paused:
        return 'Paused. New messages wait until you resume.';
      case ConnectionStatus.connected:
      case ConnectionStatus.syncing:
      case ConnectionStatus.connecting:
      case ConnectionStatus.pairing:
        return null;
    }
  }
}
