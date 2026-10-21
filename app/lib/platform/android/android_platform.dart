import 'dart:async';

import 'package:flutter/services.dart';
import 'package:twindrop_core/core.dart';

/// Dart side of the Android channel contract declared in
/// `app/android/.../TwindropChannels.kt`. Every method is safe to call on
/// non-Android platforms: the MissingPluginException is turned into a typed
/// failure only when a caller actually needs the result.
class AndroidPlatform {
  static const MethodChannel _shareQueue = MethodChannel(
    'twindrop/share_queue',
  );
  static const MethodChannel _keepAlive = MethodChannel('twindrop/keepalive');
  static const MethodChannel _network = MethodChannel('twindrop/network');
  static const MethodChannel _app = MethodChannel('twindrop/app');
  static const MethodChannel _notifications = MethodChannel(
    'twindrop/notifications',
  );
  static const MethodChannel _sharePanel = MethodChannel(
    'twindrop/share_panel',
  );

  static const int requestNotificationsCode = 7101;

  static Future<List<Map<String, dynamic>>> readShareQueue() async {
    try {
      final raw = await _shareQueue.invokeMethod<List<dynamic>>('readPending');
      return (raw ?? const <dynamic>[])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList(growable: false);
    } on PlatformException {
      return const <Map<String, dynamic>>[];
    } on MissingPluginException {
      return const <Map<String, dynamic>>[];
    }
  }

  static Future<void> ackShares(List<String> ids) async {
    try {
      await _shareQueue.invokeMethod<bool>('ack', {'shareIds': ids});
    } on PlatformException {
      // Already imported; the next launch retries idempotently.
    } on MissingPluginException {
      // Not Android.
    }
  }

  static Future<String?> consumeLaunchShareId() async {
    try {
      return await _shareQueue.invokeMethod<String>('consumeLaunchShareId');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Future<bool> isKeepAliveRunning() async {
    try {
      return await _keepAlive.invokeMethod<bool>('isRunning') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// True when the user paused the connection from the notification.
  static Future<bool> isKeepAlivePaused() async {
    try {
      return await _keepAlive.invokeMethod<bool>('isPaused') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// The native side pushes `onShareReceived` when a share intent lands while
  /// the app is running. The payload only signals that the queue changed; the
  /// text itself is read from the native queue, never from the push payload.
  static void listenShareIntents(void Function(Map<String, dynamic>) onShare) {
    _shareQueue.setMethodCallHandler((call) async {
      if (call.method == 'onShareReceived' && call.arguments is Map) {
        onShare(Map<String, dynamic>.from(call.arguments as Map));
      }
      return null;
    });
  }

  static Future<bool> startKeepAlive({String? desktopName}) async {
    try {
      return await _keepAlive.invokeMethod<bool>('start', {
            'desktopName': desktopName,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> stopKeepAlive() async {
    try {
      await _keepAlive.invokeMethod<bool>('stop');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  static Future<void> setKeepAliveStatus({
    String? desktopName,
    required bool connected,
    bool? paused,
  }) async {
    try {
      await _keepAlive.invokeMethod<bool>('setStatus', {
        'desktopName': desktopName,
        'connected': connected,
        'paused': paused,
      });
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  static Future<bool> isBatteryOptimizationIgnored() async {
    try {
      return await _keepAlive.invokeMethod<bool>(
            'isBatteryOptimizationIgnored',
          ) ??
          false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  static Future<void> requestIgnoreBatteryOptimizations() async {
    try {
      await _keepAlive.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  static Future<bool> isIgnoringBattery() => isBatteryOptimizationIgnored();

  static Future<void> acquireMulticastLock() async {
    try {
      await _keepAlive.invokeMethod<bool>('acquireMulticastLock');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  static Future<void> releaseMulticastLock() async {
    try {
      await _keepAlive.invokeMethod<bool>('releaseMulticastLock');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  static Future<bool> areNotificationsEnabled() async {
    try {
      return await _app.invokeMethod<bool>('areNotificationsEnabled') ?? false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> requestNotificationPermission() async {
    try {
      return await _app.invokeMethod<bool>('requestNotificationPermission') ??
          false;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> openNotificationSettings() async {
    try {
      await _app.invokeMethod<bool>('openNotificationSettings');
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // ignore
    }
  }

  static Future<Map<String, dynamic>> version() async {
    try {
      final raw = await _app.invokeMethod<Map<dynamic, dynamic>>('getVersion');
      return raw == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(raw);
    } on MissingPluginException {
      return const <String, dynamic>{};
    } on PlatformException {
      return const <String, dynamic>{};
    }
  }

  static Future<Map<String, dynamic>> platformInfo() async {
    try {
      final raw = await _app.invokeMethod<Map<dynamic, dynamic>>(
        'getPlatformInfo',
      );
      return raw == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(raw);
    } on MissingPluginException {
      return const <String, dynamic>{};
    } on PlatformException {
      return const <String, dynamic>{};
    }
  }

  static Future<Map<String, dynamic>> currentNetwork() async {
    try {
      final raw = await _network.invokeMethod<Map<dynamic, dynamic>>(
        'getCurrent',
      );
      return raw == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(raw);
    } on MissingPluginException {
      return const <String, dynamic>{};
    } on PlatformException {
      return const <String, dynamic>{};
    }
  }

  /// Registered once by the UI entrypoint; the native monitor pushes
  /// `networkChanged` so the connection manager retries immediately.
  static void listenNetworkChanges(
    void Function(Map<String, dynamic>) onChanged,
  ) {
    _network.setMethodCallHandler((call) async {
      if (call.method == 'networkChanged' && call.arguments is Map) {
        onChanged(Map<String, dynamic>.from(call.arguments as Map));
      }
      return null;
    });
  }

  static Future<void> showMessageNotification({
    required String deviceName,
    required String preview,
  }) async {
    try {
      await _notifications.invokeMethod<bool>('showMessage', {
        'deviceName': deviceName,
        'preview': preview,
      });
    } on MissingPluginException {
      // ignore
    } on PlatformException {
      // POST_NOTIFICATIONS denied.
    }
  }

  // ---- share panel engine ----

  static Future<Map<String, dynamic>> getPanelPayload() async {
    final raw = await _sharePanel.invokeMethod<Map<dynamic, dynamic>>(
      'getPanelPayload',
    );
    return raw == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(raw);
  }

  static Future<void> finishPanel(String action) async {
    try {
      await _sharePanel.invokeMethod<bool>('finishPanel', {'action': action});
    } on MissingPluginException {
      // ignore
    }
  }

  /// The native side pushes `panelShown` / `panelChanged` when the panel
  /// activity attaches or a second share arrives while the panel is open.
  static void listenPanelChanges(
    void Function(Map<String, dynamic>) onChanged,
  ) {
    _sharePanel.setMethodCallHandler((call) async {
      if ((call.method == 'panelShown' || call.method == 'panelChanged') &&
          call.arguments is Map) {
        onChanged(Map<String, dynamic>.from(call.arguments as Map));
      }
      return null;
    });
  }
}

class AndroidMulticastLock implements MulticastLock {
  @override
  Future<void> acquire() => AndroidPlatform.acquireMulticastLock();

  @override
  Future<void> release() => AndroidPlatform.releaseMulticastLock();
}

/// Shows incoming messages with Android notifications and mirrors the
/// connection state into the persistent keep-alive notification.
class AndroidNotifier implements CoreNotifier {
  @override
  Future<void> onIncomingItem(Item item) async {
    if (!item.isMessage) return;
    final preview = item.text.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (preview.isEmpty) return;
    await AndroidPlatform.showMessageNotification(
      deviceName: item.originName,
      preview: preview.length <= 80 ? preview : preview.substring(0, 80),
    );
  }

  @override
  Future<void> onConnectionChanged(ConnectionStatus status) async {
    await AndroidPlatform.setKeepAliveStatus(
      connected:
          status == ConnectionStatus.connected ||
          status == ConnectionStatus.syncing,
      paused: status == ConnectionStatus.paused,
    );
  }

  @override
  Future<void> clear() async {
    // No persisted notification content exists to clear.
  }
}
