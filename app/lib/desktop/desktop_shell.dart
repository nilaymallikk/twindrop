import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Brightness, Offset, PlatformDispatcher, Size;

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter/widgets.dart' show Alignment, WidgetsFlutterBinding;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'shell_args.dart';

export 'autostart.dart';
export 'notifications.dart';
export 'shell_args.dart';
export 'single_instance.dart';

/// Callbacks the host implements. Every tray/menu entry maps to one.
class DesktopActions {
  const DesktopActions({
    required this.onOpenMain,
    required this.onOpenPopup,
    required this.onQuit,
    required this.onSendClipboard,
    required this.onTogglePause,
  });

  final VoidCallback onOpenMain;
  final VoidCallback onOpenPopup;
  final VoidCallback onQuit;
  final VoidCallback onSendClipboard;
  final VoidCallback onTogglePause;
}

enum _WindowMode { none, main, popup }

/// Owns the one native window, the tray icon, and tray-driven actions.
class DesktopShell with WindowListener {
  DesktopShell._(this._actions);

  static const _mainSize = Size(900, 640);
  static const _popupSize = Size(380, 520);
  static const _popupRightMargin = 12.0;
  static const _popupTopMargin = 48.0; // 36 px panel + 12 px gap.

  final DesktopActions _actions;

  TrayIcon? _tray;
  Menu? _menu;
  MenuItem? _statusItem;
  MenuItem? _pauseItem;
  ListenerId? _trayListenerId;
  bool _trayAvailable = false;
  bool _trayVisible = false;
  bool _darkPanel = true;
  bool _hideOnBlur = true;
  bool _paused = false;
  bool _connected = false;
  int _unread = 0;
  String _statusLabel = 'Offline';
  _WindowMode _mode = _WindowMode.none;

  /// Whether a tray icon is actually visible and usable for this session.
  bool get hasTray => _trayVisible && _trayAvailable && _tray != null;

  static Future<DesktopShell> start({
    required DesktopActions actions,
    required ShellArgs args,
    required bool startHidden,
  }) async {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();

    final shell = DesktopShell._(actions);
    await shell._prepareWindow();
    await shell._createTray();

    if (args.quit) {
      await shell.hide();
    } else if (args.quickSend) {
      await shell.showPopup();
    } else if (args.open) {
      await shell.showMain();
    } else if ((startHidden || args.hidden) && shell.hasTray) {
      await shell.hide();
    } else {
      // No confirmed tray means an invisible window would strand the app.
      await shell.showMain();
    }
    return shell;
  }

  Future<void> _prepareWindow() async {
    windowManager.addListener(this);
    try {
      await windowManager.setPreventClose(true);
    } catch (_) {
      // Closing then exits through the platform default instead.
    }
    await windowManager.setResizable(true);
    await windowManager.setSize(_mainSize);
  }

  Future<void> _createTray() async {
    try {
      if (!await _hasStatusNotifierWatcher()) return;

      final tray = TrayIcon.createWithIdentifier('twindrop');
      if (tray == null) return;
      _tray = tray;
      _trayAvailable = true;
      _trayVisible = true;

      _darkPanel = await _isDarkPanel();
      _applyTrayIcon();
      tray.setTooltip('TwinDrop - $_statusLabel');
      _buildMenu();
      if (_menu != null) tray.setContextMenu(_menu);
      _trayListenerId = tray.addListener(_onTrayEvent);
    } catch (_) {
      _trayAvailable = false;
    }
  }

  Future<void> setStatus({
    required String label,
    required bool connected,
    required int unread,
  }) async {
    _statusLabel = label;
    _connected = connected;
    _unread = unread < 0 ? 0 : unread;
    _applyTrayIcon();
    _tray?.setTooltip('TwinDrop - $_statusLabel');
    _refreshMenuLabels();
  }

  Future<void> setPaused(bool paused) async {
    _paused = paused;
    _applyTrayIcon();
    _refreshMenuLabels();
  }

  Future<void> setHideOnBlur(bool enabled) async {
    _hideOnBlur = enabled;
  }

  Future<void> showPopup() async {
    _mode = _WindowMode.popup;
    await _bestEffort(() => windowManager.setResizable(false));
    await _bestEffort(() => windowManager.setSkipTaskbar(true));
    await _bestEffort(() => windowManager.setAlwaysOnTop(true));
    await windowManager.setSize(_popupSize);
    await windowManager.show();
    await _positionPopup();
    await windowManager.focus();
  }

  Future<void> showMain() async {
    _mode = _WindowMode.main;
    await _bestEffort(() => windowManager.setAlwaysOnTop(false));
    await _bestEffort(() => windowManager.setSkipTaskbar(false));
    await _bestEffort(() => windowManager.setResizable(true));
    await windowManager.setSize(_mainSize);
    await _bestEffort(
      () => windowManager.setAlignment(Alignment.center),
    );
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> hide() async {
    // Never hide into nothing: without a tray the window is the only way back.
    if (!hasTray) return;
    _mode = _WindowMode.none;
    await _bestEffort(() => windowManager.setAlwaysOnTop(false));
    await windowManager.hide();
  }

  Future<void> setTrayVisible(bool visible) async {
    _trayVisible = visible && _trayAvailable;
    _tray?.setVisible(_trayVisible);
    if (!hasTray && !await windowManager.isVisible()) {
      await showMain();
    }
  }

  Future<void> _positionPopup() async {
    await _bestEffort(() async {
      await windowManager.setAlignment(Alignment.topRight);
      final position = await windowManager.getPosition();
      await windowManager.setPosition(
        Offset(
          position.dx - _popupRightMargin,
          position.dy + _popupTopMargin,
        ),
      );
    });
  }

  void _buildMenu() {
    final menu = Menu.create();
    if (menu == null) return;

    MenuItem? entry(String label, VoidCallback? callback) {
      final item = MenuItem.createWithLabelAndType(
        label,
        MenuItemType.normal,
      );
      if (item == null) return null;
      if (callback == null) {
        item.isEnabled = false;
      } else {
        item.addListener((event) {
          if (event is MenuItemClickedEvent) callback();
        });
      }
      menu.addItem(item);
      return item;
    }

    entry('Open TwinDrop', _actions.onOpenMain);
    entry('Send clipboard to phone', _actions.onSendClipboard);
    _statusItem = entry(_statusText, null);
    _pauseItem = entry(_pauseLabel, _actions.onTogglePause);
    final separator = MenuItem.createWithLabelAndType(
      '',
      MenuItemType.separator,
    );
    if (separator != null) menu.addItem(separator);
    entry('Quit', _actions.onQuit);

    final previous = _menu;
    _menu = menu;
    if (previous != null) {
      // The native menu may still be referencing the old handle.
      Timer.run(previous.dispose);
    }
  }

  void _refreshMenuLabels() {
    _statusItem?.label = _statusText;
    _pauseItem?.label = _pauseLabel;
  }

  String get _statusText {
    final base = _paused ? 'Paused' : _statusLabel;
    if (!_paused && _connected && _unread > 0) {
      return '$base - $_unread unread';
    }
    return base;
  }

  String get _pauseLabel => _paused ? 'Resume connection' : 'Pause connection';

  void _onTrayEvent(TrayIconEvent event) {
    if (event is TrayIconClickedEvent) {
      unawaited(_togglePopup());
    }
  }

  Future<void> _togglePopup() async {
    final visible = await windowManager.isVisible();
    if (visible && _mode == _WindowMode.popup) {
      await hide();
    } else {
      await showPopup();
    }
  }

  void _applyTrayIcon() {
    final tray = _tray;
    if (tray == null) return;
    final state = (_connected && !_paused)
        ? (_unread > 0 ? 'unread' : 'connected')
        : 'offline';
    final variant = _darkPanel ? 'white' : 'black';
    final icon = ImageAsset.fromAsset(
      'assets/tray/$state-$variant-24.png',
    );
    if (icon != null) tray.icon = icon;
  }

  @override
  void onWindowClose() {
    unawaited(_handleClose());
  }

  Future<void> _handleClose() async {
    if (hasTray) {
      await hide();
    } else {
      _actions.onQuit();
    }
  }

  @override
  void onWindowBlur() {
    if (_mode == _WindowMode.popup && _hideOnBlur && hasTray) {
      unawaited(hide());
    }
  }

  Future<void> dispose() async {
    windowManager.removeListener(this);
    await _bestEffort(() => windowManager.setPreventClose(false));
    final listener = _trayListenerId;
    if (listener != null) _tray?.removeListener(listener);
    _trayListenerId = null;
    _tray?.dispose();
    _tray = null;
    _trayAvailable = false;
    _trayVisible = false;
    _menu?.dispose();
    _menu = null;
    _statusItem = null;
    _pauseItem = null;
  }

  static Future<bool> _hasStatusNotifierWatcher() async {
    if (!Platform.isLinux) return true;
    try {
      final result = await Process.run('gdbus', [
        'call',
        '--session',
        '--dest',
        'org.freedesktop.DBus',
        '--object-path',
        '/org/freedesktop/DBus',
        '--method',
        'org.freedesktop.DBus.NameHasOwner',
        'org.kde.StatusNotifierWatcher',
      ], stdoutEncoding: utf8).timeout(const Duration(seconds: 2));
      if (result.exitCode != 0) return false;
      return '${result.stdout}'.contains('true');
    } catch (_) {
      // No gdbus or no session bus: treat as unknown/absent, never install
      // or probe extensions.
      return false;
    }
  }

  Future<bool> _isDarkPanel() async {
    final gtkTheme = Platform.environment['GTK_THEME']?.toLowerCase() ?? '';
    if (gtkTheme.contains('dark')) return true;

    if (Platform.isLinux) {
      final scheme = await _gsettings('color-scheme');
      if (scheme.contains('prefer-dark')) return true;
      if (scheme.contains('prefer-light')) return false;
      final theme = await _gsettings('gtk-theme');
      if (theme.contains('dark')) return true;
      if (theme.isNotEmpty) return false;
    }

    try {
      return PlatformDispatcher.instance.platformBrightness == Brightness.dark;
    } catch (_) {
      return true;
    }
  }

  static Future<String> _gsettings(String key) async {
    try {
      final result = await Process.run(
        'gsettings',
        ['get', 'org.gnome.desktop.interface', key],
        stdoutEncoding: utf8,
      ).timeout(const Duration(milliseconds: 800));
      return result.exitCode == 0 ? '${result.stdout}'.toLowerCase() : '';
    } catch (_) {
      return '';
    }
  }

  static Future<void> _bestEffort(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Window managers differ (notably Wayland positioning); core flow wins.
    }
  }
}
