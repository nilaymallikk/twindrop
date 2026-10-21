import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:twindrop_core/core.dart';

import 'bootstrap/app_paths.dart';
import 'platform/android/android_platform.dart';
import 'state/app_controller.dart';

/// Headless keep-alive engine (docs/06 §2).
///
/// The Android foreground service hosts this isolate so the pinned WSS
/// connection to the paired desktop survives the UI being closed. It uses the
/// exact same [CoreRuntime] and [ConnectionManager] as the UI — there is no
/// second protocol implementation.
///
/// The engine owns nothing the UI needs to see: the replica is a SQLite file
/// both isolates open, and the device token lives in secure storage, so the
/// two isolates stay in sync without messaging each other.
Future<void> runKeepAlive() async {
  WidgetsFlutterBinding.ensureInitialized();

  final paths = await AppPaths.resolve();
  final runtime = await CoreRuntime.open(
    platform: CorePlatform.phone,
    deviceName: 'TwinDrop',
    dataDir: paths.supportDir.path,
    tokenStore: SecureTokenStore(),
    multicastLock: AndroidMulticastLock(),
    notifier: AndroidNotifier(),
  );

  // The notification's Pause/Resume action writes a native preference; the
  // engine mirrors it into the core so both isolates agree.
  var paused = await AndroidPlatform.isKeepAlivePaused();
  if (paused) await runtime.pause();

  runtime.statusStream.listen((status) {
    unawaited(_mirrorStatus(runtime, status));
  });

  AndroidPlatform.listenNetworkChanges((_) => runtime.retryNow());

  await runtime.start();
  await _mirrorStatus(runtime, runtime.status);

  // Poll the native pause preference so the notification's Pause button works
  // even when the app itself is not running.
  Timer.periodic(const Duration(seconds: 2), (_) async {
    final nativePaused = await AndroidPlatform.isKeepAlivePaused();
    if (nativePaused == paused) return;
    paused = nativePaused;
    if (paused) {
      await runtime.pause();
    } else {
      await runtime.resume();
    }
  });
}

/// Mirrors the connection state into the persistent notification.
Future<void> _mirrorStatus(CoreRuntime runtime, ConnectionStatus status) async {
  final active = await runtime.peers.active();
  await AndroidPlatform.setKeepAliveStatus(
    desktopName: active.isEmpty ? null : active.first.name,
    connected: status == ConnectionStatus.connected ||
        status == ConnectionStatus.syncing,
    paused: status == ConnectionStatus.paused,
  );
}
