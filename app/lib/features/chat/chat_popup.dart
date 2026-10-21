import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twindrop_core/models/enums.dart';

import '../../theme/context_ext.dart';
import '../../widgets/primitives.dart';
import '../models.dart';
import 'chat_screen.dart';

/// The desktop tray popup: a 380×520 [ChatScreen] on a raised, hairline-bordered
/// surface with a 12 px radius (docs/13 §6). The host owns the window size; this
/// widget only renders the surface, and the header's Open action is required so
/// the popup is never a dead end.
class ChatPopup extends StatelessWidget {
  const ChatPopup({
    super.key,
    required this.entries,
    required this.status,
    required this.onOpenApp,
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
    this.onClose,
    this.composerFocusNode,
    this.pasteSuggestion,
    this.hasMore = false,
    this.onLoadOlder,
    this.onSendClipboard,
  });

  final List<ChatEntry> entries;
  final ConnectionStatus status;
  final VoidCallback onOpenApp;
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
  final VoidCallback? onClose;
  final FocusNode? composerFocusNode;
  final String? pasteSuggestion;
  final bool hasMore;
  final VoidCallback? onLoadOlder;

  /// Ctrl+Shift+V — send the clipboard as a message (LNX-003).
  final VoidCallback? onSendClipboard;

  @override
  Widget build(BuildContext context) {
    final tokens = context.td;
    const radius = 12.0;
    return CallbackShortcuts(
      // LNX-003: the popup is keyboard driven. The Focus must sit *inside* the
      // shortcuts so the primary focus node is a descendant of them.
      bindings: <ShortcutActivator, VoidCallback>{
        if (onClose != null)
          const SingleActivator(LogicalKeyboardKey.escape): onClose!,
        if (onSendClipboard != null)
          const SingleActivator(
            LogicalKeyboardKey.keyV,
            control: true,
            shift: true,
          ): onSendClipboard!,
        if (entries.isNotEmpty)
          const SingleActivator(
            LogicalKeyboardKey.keyS,
            control: true,
          ): () => onSaveToNotepad(entries.last),
      },
      child: Focus(
        autofocus: true,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380, maxHeight: 520),
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: TdSurface(
                color: tokens.bg,
                radius: radius,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: ChatScreen(
                    entries: entries,
                    status: status,
                    peerName: peerName,
                    isLoading: isLoading,
                    errorMessage: errorMessage,
                    onRetry: onRetry,
                    onTroubleshoot: onTroubleshoot,
                    onSend: onSend,
                    onSaveToNotepad: onSaveToNotepad,
                    onDelete: onDelete,
                    onCopy: onCopy,
                    onOpenLink: onOpenLink,
                    onShowNotepad: onShowNotepad,
                    onShowSettings: onShowSettings,
                    isPopup: true,
                    onClose: onClose,
                    composerFocusNode: composerFocusNode,
                    pasteSuggestion: pasteSuggestion,
                    hasMore: hasMore,
                    onLoadOlder: onLoadOlder,
                    onOpenApp: onOpenApp,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
