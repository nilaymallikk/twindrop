import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twindrop_core/core.dart';
import 'package:url_launcher/url_launcher.dart';

import 'features/chat/chat_popup.dart';
import 'features/chat/chat_screen.dart';
import 'features/format.dart';
import 'features/models.dart';
import 'features/notepad/note_editor.dart';
import 'features/notepad/notepad_screen.dart';
import 'features/notepad/save_to_notepad_sheet.dart';
import 'features/pairing/desktop_pairing_screen.dart';
import 'features/pairing/phone_onboarding_screen.dart';
import 'features/settings/diagnostics_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'platform/android/android_platform.dart';
import 'state/app_controller.dart';
import 'theme/theme.dart';
import 'theme/tokens.dart';
import 'widgets/states.dart';

/// Application root. Pure presentation over [AppController]; every action goes
/// through the controller so phone, desktop window and popup share one path.
class TwinDropApp extends StatefulWidget {
  const TwinDropApp({
    super.key,
    required this.controller,
    this.desktop = false,
  });

  final AppController controller;
  final bool desktop;

  @override
  State<TwinDropApp> createState() => _TwinDropAppState();
}

class _TwinDropAppState extends State<TwinDropApp> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  final FocusNode _composerFocus = FocusNode(debugLabel: 'composer');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    WidgetsBinding.instance.removeObserver(this);
    _composerFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(widget.controller.onLifecycleChanged(state));
  }

  void _onControllerChanged() {
    final toast = widget.controller.toast;
    if (toast == null) return;
    widget.controller.clearToast();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _messengerKey.currentState
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(toast),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return MaterialApp(
          title: 'TwinDrop',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: _messengerKey,
          theme: buildTdTheme(
            choice: controller.themeChoice,
            platformBrightness: Brightness.light,
          ),
          darkTheme: buildTdTheme(
            choice: controller.themeChoice,
            platformBrightness: Brightness.dark,
          ),
          themeMode: switch (controller.themeChoice) {
            AppThemeChoice.light => ThemeMode.light,
            AppThemeChoice.system => ThemeMode.system,
            _ => ThemeMode.dark,
          },
          home: _Root(
            controller: controller,
            desktop: widget.desktop,
            composerFocus: _composerFocus,
          ),
        );
      },
    );
  }
}

class _Root extends StatelessWidget {
  const _Root({
    required this.controller,
    required this.desktop,
    required this.composerFocus,
  });

  final AppController controller;
  final bool desktop;
  final FocusNode composerFocus;

  @override
  Widget build(BuildContext context) {
    if (!controller.initialized) {
      return const Scaffold(body: TdLoadingState(label: 'Starting TwinDrop'));
    }
    if (controller.fatalError != null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: TdErrorState(
              message: controller.fatalError!,
              actionLabel: 'Try again',
              onAction: () => controller.init(),
            ),
          ),
        ),
      );
    }

    if (controller.isPhone &&
        controller.activePeer == null &&
        controller.phoneOnboarding.stage != PhoneOnboardingStage.connected) {
      return _onboarding(context);
    }

    if (desktop && controller.popupMode) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: ChatPopup(
          entries: controller.messages,
          status: controller.status,
          peerName: controller.activePeer?.name,
          isLoading: controller.loadingChat,
          errorMessage: controller.chatError,
          onRetry: controller.retryNow,
          onTroubleshoot: () => _openDiagnostics(context),
          onSend: controller.sendMessage,
          onSaveToNotepad: (entry) => _saveToNotepad(context, entry),
          onDelete: (entry) => controller.deleteMessage(entry.id),
          onCopy: (entry) => _copy(context, entry.text),
          onOpenLink: (url) => _openLink(context, url),
          onOpenApp: () => controller.desktopHooks.onShowMain?.call(),
          onClose: () => controller.desktopHooks.onHideWindow?.call(),
          composerFocusNode: composerFocus,
          pasteSuggestion: null,
        ),
      );
    }

    return AppShell(
      section: controller.section,
      onSectionChanged: controller.setSection,
      status: controller.status,
      peerName: controller.activePeer?.name,
      showSidebar: desktop,
      unreadChat: controller.unreadChat,
      child: switch (controller.section) {
        AppSection.chat => _chat(context),
        AppSection.notepad => _notepad(context),
        AppSection.settings => _settings(context),
      },
    );
  }

  Widget _chat(BuildContext context) {
    if (controller.isDesktop && controller.activePeer == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(TdSpace.s24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _desktopPairing(),
          ),
        ),
      );
    }
    return ChatScreen(
      entries: controller.messages,
      status: controller.status,
      peerName: controller.activePeer?.name,
      isLoading: controller.loadingChat,
      errorMessage: controller.chatError,
      onRetry: controller.retryNow,
      onTroubleshoot: () => _openDiagnostics(context),
      onSend: controller.sendMessage,
      onSaveToNotepad: (entry) => _saveToNotepad(context, entry),
      onDelete: (entry) => controller.deleteMessage(entry.id),
      onCopy: (entry) => _copy(context, entry.text),
      onOpenLink: (url) => _openLink(context, url),
      onShowNotepad: () => controller.setSection(AppSection.notepad),
      onShowSettings: () => controller.setSection(AppSection.settings),
      showKeyboardHint: controller.isDesktop,
      composerFocusNode: controller.isDesktop ? composerFocus : null,
    );
  }

  Widget _desktopPairing() {
    final stage = controller.desktopPairing.stage;
    if (stage == DesktopPairingStage.idle) {
      return DesktopPairingScreen(
        data: controller.desktopPairing,
        onStart: () => controller.startPairing(),
        onCancel: controller.cancelPairing,
        onApprove: controller.approvePairing,
        onReject: controller.rejectPairing,
      );
    }
    return DesktopPairingScreen(
      data: controller.desktopPairing,
      onStart: () => controller.startPairing(),
      onCancel: controller.cancelPairing,
      onApprove: controller.approvePairing,
      onReject: controller.rejectPairing,
      onRetry: () => controller.startPairing(),
    );
  }

  Widget _onboarding(BuildContext context) {
    return PhoneOnboardingScreen(
      data: controller.phoneOnboarding,
      onStartScan: controller.beginScan,
      onSubmitQr: controller.pairWithQr,
      onManualEntry: controller.beginManual,
      onConfirmFingerprint: controller.confirmManualFingerprint,
      onSubmitManual: controller.submitManual,
      onPermissionDecided: (step) => controller.decidePermission(
        step.permission,
        granted: step.granted,
        skipped: step.skipped,
      ),
      onSkip: (permission) => controller.decidePermission(
        permission,
        granted: false,
        skipped: true,
      ),
      onCancel: () => controller.beginManual(),
      onDone: () => controller.finishOnboarding(),
    );
  }

  Widget _notepad(BuildContext context) {
    return NotepadScreen(
      categories: controller.categories,
      notes: controller.notes,
      selectedCategoryId: controller.selectedCategoryId,
      categoryNames: {
        for (final category in controller.categories)
          category.id: category.name,
      },
      searchQuery: controller.searchQuery,
      isLoading: controller.loadingNotes,
      errorMessage: controller.notesError,
      onRetry: controller.refresh,
      onCategorySelected: controller.selectCategory,
      onSearchChanged: controller.setSearchQuery,
      onCreateNote: () => _openNoteEditor(context, null),
      onOpenNote: (note) => _openNoteEditor(context, note),
      onTogglePin: controller.togglePinned,
      onDeleteNote: controller.deleteNote,
      onOpenLink: (url) => _openLink(context, url),
      categoryActions: controller.categoryActions,
      showSidebar: controller.isDesktop,
      undo: controller.noteUndo,
    );
  }

  Widget _settings(BuildContext context) {
    final peer = controller.activePeer;
    final diag = controller.diagnostics;
    return SettingsScreen(
      status: controller.status,
      peerName: peer?.name,
      peerLabel: peer == null
          ? null
          : (peer.lastHost != null && peer.lastPort != null
              ? '${peer.lastHost}:${peer.lastPort}'
              : peer.kind.wire),
      deviceId: controller.runtime?.deviceId,
      deviceName: controller.deviceName,
      localAddresses: diag?.localAddresses ?? const <String>[],
      lastSyncLabel: peer?.lastSeen == null
          ? null
          : tdRelativeLabel(peer!.lastSeen!),
      queueCount: diag?.queuedItems ?? 0,
      serverState: controller.isDesktop
          ? ((diag?.serverRunning ?? false)
              ? 'Running on port ${diag?.port}'
              : 'Stopped')
          : null,
      ipPort: controller.isDesktop
          ? ((diag?.localAddresses.isNotEmpty ?? false)
              ? '${diag!.localAddresses.first}:${diag.port}'
              : null)
          : (peer?.lastHost != null ? '${peer!.lastHost}:${peer.lastPort}' : null),
      themeChoice: controller.themeChoice,
      onThemeChanged: controller.setTheme,
      notifications: controller.notifications,
      onNotificationsChanged: controller.setNotifications,
      notificationsSupported: controller.notificationsSupported,
      shareAction: controller.shareAction,
      onShareActionChanged: controller.setShareAction,
      cleanLinks: controller.cleanLinks,
      onCleanLinksChanged: controller.setCleanLinks,
      paused: controller.paused,
      onPauseChanged: controller.setPaused,
      onRevoke: peer == null
          ? null
          : () => _confirm(
                context,
                title: 'Remove ${peer.name}?',
                message:
                    'Its token is revoked and its live connection is closed. '
                    'You can pair it again later.',
                confirmLabel: 'Remove',
                onConfirmed: () => controller.revokePeer(peer.id),
              ),
      onUnpair: peer == null
          ? null
          : () => _confirm(
                context,
                title: 'Unpair this device?',
                message: 'Local data stays on this device. The desktop can '
                    'revoke the token later if it is offline.',
                confirmLabel: 'Unpair',
                onConfirmed: () async {
                  await controller.unpair();
                },
              ),
      onRetryNow: controller.retryNow,
      onExportMarkdown: () => controller.exportNotepad(markdown: true),
      onExportJson: () => controller.exportNotepad(markdown: false),
      onClearData: () => _confirm(
        context,
        title: 'Clear all TwinDrop data?',
        message: 'Messages, notes, categories, pairing and tokens on this '
            'device are deleted. This cannot be undone.',
        confirmLabel: 'Clear everything',
        destructive: true,
        onConfirmed: controller.clearAllData,
      ),
      onOpenDiagnostics: () => _openDiagnostics(context),
      onPairAgain: () {
        if (controller.isDesktop) {
          controller.setSection(AppSection.chat);
          controller.startPairing();
        } else {
          unawaited(controller.unpair().then((_) => controller.beginManual()));
        }
      },
      keepAliveSupported: controller.keepAliveSupported,
      keepAliveEnabled: controller.keepAliveEnabled,
      onKeepAliveChanged: (value) async {
        if (value) {
          await AndroidPlatform.startKeepAlive(
              desktopName: controller.activePeer?.name);
        } else {
          await AndroidPlatform.stopKeepAlive();
        }
      },
      batteryOptimized: controller.batteryOptimized,
      onBatterySettings: AndroidPlatform.requestIgnoreBatteryOptimizations,
      autostartSupported: controller.autostartSupported,
      autostart: controller.autostart,
      onAutostartChanged: controller.setAutostart,
      hideOnBlur: controller.hideOnBlur,
      onHideOnBlurChanged: controller.setHideOnBlur,
      quickSendCommand: controller.quickSendCommand,
      onCopyQuickSend: () => _copy(context, controller.quickSendCommand),
      appVersion: controller.appVersion,
      isDesktop: controller.isDesktop,
      trayAvailable: controller.trayAvailable,
      quarantineCount: diag?.quarantineCount ?? 0,
      onOpenQuarantine: () => _openQuarantine(context),
    );
  }

  Future<void> _saveToNotepad(BuildContext context, ChatEntry entry) async {
    final result = await showSaveToNotepadSheet(
      context,
      categories: controller.categories,
      initialCategoryId: controller.selectedCategoryId,
      onCreateCategory: (name) async =>
          await controller.categoryActions.onCreate?.call(name),
    );
    if (result == null) return;
    await controller.saveMessageAsNote(entry.id, result: result);
  }

  Future<void> _openNoteEditor(BuildContext context, Item? note) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => NoteEditorScreen(
        categories: controller.categories,
        note: note,
        initialCategoryId: controller.selectedCategoryId,
        onSave: (draft) async {
          if (note == null) {
            await controller.createNote(draft);
          } else {
            await controller.updateNote(note.id, draft);
          }
          if (context.mounted) Navigator.of(context).pop();
        },
        onCancel: () => Navigator.of(context).pop(),
        onDelete: note == null
            ? null
            : () async {
                await controller.deleteNote(note);
                if (context.mounted) Navigator.of(context).pop();
              },
      ),
    ));
  }

  Future<void> _openDiagnostics(BuildContext context) async {
    final diag = controller.diagnostics ?? await controller.runtime!.diagnostics();
    if (!context.mounted) return;
    final peer = controller.activePeer;
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => DiagnosticsScreen(
        localAddresses: diag.localAddresses,
        peerLabel: peer?.name,
        peerLastAddress: (peer == null || peer.lastHost == null)
            ? null
            : '${peer.lastHost}:${peer.lastPort}',
        mdnsSummary: diag.mdnsRunning ? 'Announcing' : 'Not available',
        pinState: diag.fingerprint == null
            ? null
            : 'Pinned ${diag.fingerprint!.substring(0, 12)}…',
        onTestConnection: controller.testConnection,
        onManualAddress: (value) async {
          await controller.setManualAddress(value);
        },
        onRetry: controller.retryNow,
        firewallHint: controller.isDesktop
            ? 'sudo firewall-cmd --add-port=${diag.port}/tcp'
            : null,
        serverPort: diag.port,
      ),
    ));
  }

  Future<void> _openQuarantine(BuildContext context) async {
    final entries = await controller.runtime!.quarantine.list();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quarantined changes'),
        content: SizedBox(
          width: 420,
          child: entries.isEmpty
              ? const Text('Nothing is quarantined.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  itemBuilder: (_, index) {
                    final entry = entries[index];
                    return ListTile(
                      dense: true,
                      title: Text('${entry.entityType} · ${entry.reason}'),
                      subtitle: Text(entry.entityId),
                    );
                  },
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required Future<void> Function() onConfirmed,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              confirmLabel,
              style: destructive
                  ? TextStyle(color: Theme.of(dialogContext).colorScheme.error)
                  : null,
            ),
          ),
        ],
      ),
    );
    if (ok == true) await onConfirmed();
  }

  Future<void> _copy(BuildContext context, String? value) async {
    if (value == null || value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied.'), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No browser could open that link.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
