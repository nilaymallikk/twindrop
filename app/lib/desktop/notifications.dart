import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Desktop notifications for incoming items. Notification text is never logged.
class DesktopNotifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final Map<int, VoidCallback> _taps = <int, VoidCallback>{};
  Future<void>? _initFuture;
  bool _available = false;
  int _nextId = 1;

  Future<void> init() {
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    if (!Platform.isLinux) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          linux: LinuxInitializationSettings(
            defaultActionName: 'Open TwinDrop',
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final id = response.id ?? int.tryParse(response.payload ?? '') ?? -1;
          _taps.remove(id)?.call();
        },
      );
      _available = true;
    } catch (_) {
      // No notification server (headless session): the app keeps working.
      _available = false;
    }
  }

  Future<void> showIncoming({
    required String deviceName,
    required String preview,
    required VoidCallback onTap,
  }) async {
    await init();
    if (!_available) return;

    final id = _nextId++;
    _taps[id] = onTap;
    // Bound the body without splitting a surrogate pair.
    final body = preview.runes.length <= 80
        ? preview
        : String.fromCharCodes(preview.runes.take(80));
    try {
      await _plugin.show(
        id: id,
        title: deviceName,
        body: body,
        payload: '$id',
        notificationDetails: const NotificationDetails(
          linux: LinuxNotificationDetails(
            category: LinuxNotificationCategory.imReceived,
          ),
        ),
      );
    } catch (_) {
      _taps.remove(id);
    }
  }

  Future<void> dispose() async {
    _taps.clear();
    if (!_available) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {
      // Shutting down; nothing useful left to recover.
    }
  }
}
