import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twindrop_core/core.dart';

import 'app.dart';
import 'bootstrap/app_paths.dart';
import 'desktop/autostart.dart';
import 'desktop/desktop_shell.dart';
import 'desktop/notifications.dart';
import 'desktop/shell_args.dart';
import 'desktop/single_instance.dart';
import 'keepalive_main.dart';
import 'platform/android/android_platform.dart';
import 'share_panel_main.dart';
import 'state/app_controller.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await _runAndroid();
    return;
  }
  if (Platform.isLinux) {
    await _runLinux(args);
    return;
  }
  // Desktop builds other than Linux are not part of v1; still show the app
  // rather than failing silently.
  await _runAndroid();
}

Future<void> _runAndroid() async {
  final paths = await AppPaths.resolve();
  late final AppController controller;
  controller = AppController(
    paths: paths,
    platform: CorePlatform.phone,
    notifier: AndroidNotifier(),
  );
  AndroidPlatform.listenNetworkChanges((_) {
    controller.runtime?.retryNow();
  });
  AndroidPlatform.listenShareIntents((share) async {
    await controller.importLaunchShare();
  });
  runApp(TwinDropApp(controller: controller));
  await controller.init();
  await AndroidPlatform.consumeLaunchShareId();
}

Future<void> _runLinux(List<String> args) async {
  final shellArgs = ShellArgs.parse(args);
  final instanceResult = await SingleInstance.acquire();
  final instance = instanceResult.instance;
  if (instanceResult.isSecondary) {
    final flag = shellArgs.forwardFlag;
    if (flag != null) {
      try {
        await instance.send(flag);
      } on Object {
        // The primary may be shutting down; a fresh launch will take over.
      }
    }
    await instance.dispose();
    exit(0);
  }
  if (shellArgs.quit) {
    await instance.dispose();
    exit(0);
  }

  final paths = await AppPaths.resolve();
  final notifications = DesktopNotifications();
  await notifications.init();
  final autostart = Autostart();

  late AppController controller;
  late DesktopShell shell;

  Future<void> quit() async {
    controller.dispose();
    await shell.dispose();
    await instance.dispose();
    await notifications.dispose();
    exit(0);
  }

  shell = await DesktopShell.start(
    args: shellArgs,
    startHidden: shellArgs.hidden,
    actions: DesktopActions(
      onOpenMain: () {
        controller.setPopupMode(false);
        unawaited(shell.showMain());
      },
      onOpenPopup: () {
        controller.setPopupMode(true);
        unawaited(shell.showPopup());
      },
      onQuit: () => unawaited(quit()),
      onSendClipboard: () async {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text?.trim();
        if (text != null && text.isNotEmpty) {
          await controller.sendMessage(text);
        } else {
          controller.showToast('The clipboard has no text.');
        }
      },
      onTogglePause: () {
        unawaited(controller.setPaused(!controller.paused));
      },
    ),
  );

  final appImage = Platform.environment['APPIMAGE'];
  final executable = (appImage != null && appImage.isNotEmpty)
      ? appImage
      : Platform.resolvedExecutable;

  controller = AppController(
    paths: paths,
    platform: CorePlatform.desktop,
    notifier: _DesktopNotifier(notifications, shell),
    desktopHooks: DesktopHooks(
      onStatus: ({
        required String label,
        required bool connected,
        required int unread,
      }) => shell.setStatus(label: label, connected: connected, unread: unread),
      onPaused: shell.setPaused,
      isAutostartEnabled: autostart.isEnabled,
      setAutostart: (enabled) =>
          autostart.setEnabled(enabled, command: '$executable --hidden'),
      isTrayAvailable: () => shell.hasTray,
      quickSendCommand: '$executable --quick-send',
      onShowMain: () {
        controller.setPopupMode(false);
        unawaited(shell.showMain());
      },
      onShowPopup: () {
        controller.setPopupMode(true);
        unawaited(shell.showPopup());
      },
      onHideWindow: () => shell.hide(),
    ),
  );

  await controller.init();
  await shell.setStatus(
    label: controller.status.isOnline ? 'Connected' : 'Offline',
    connected: controller.status.isOnline,
    unread: controller.unreadChat,
  );
  await shell.setPaused(controller.paused);
  controller.setPopupMode(shellArgs.quickSend);

  instance.commands.listen((command) {
    switch (command) {
      case '--open':
        controller.setPopupMode(false);
        unawaited(shell.showMain());
      case '--quick-send':
        controller.setPopupMode(true);
        unawaited(shell.showPopup());
      case '--quit':
        unawaited(quit());
    }
  });

  runApp(TwinDropApp(controller: controller, desktop: true));
}

class _DesktopNotifier implements CoreNotifier {
  _DesktopNotifier(this._notifications, this._shell);

  final DesktopNotifications _notifications;
  final DesktopShell _shell;

  @override
  Future<void> onIncomingItem(Item item) async {
    if (!item.isMessage) return;
    final preview = item.text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (preview.isEmpty) return;
    await _notifications.showIncoming(
      deviceName: item.originName,
      preview: preview,
      onTap: () => _shell.showPopup(),
    );
  }

  @override
  Future<void> onConnectionChanged(ConnectionStatus status) async {}

  @override
  Future<void> clear() async {}
}

/// Headless Android entrypoint. The foreground service owns the connection
/// while the UI is backgrounded.
@pragma('vm:entry-point')
Future<void> keepAliveMain() => runKeepAlive();

/// Share-panel entrypoint: a tiny engine showing the confirmation sheet.
@pragma('vm:entry-point')
void sharePanelMain() => runSharePanel();
