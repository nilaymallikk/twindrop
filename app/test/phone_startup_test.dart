import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twindrop/bootstrap/app_paths.dart';
import 'package:twindrop/platform/android/android_platform.dart';
import 'package:twindrop/state/app_controller.dart';
import 'package:twindrop_core/core.dart';

/// Runs the **phone** startup path off-device.
///
/// The desktop path is covered by the real AppImage launch, but the phone path
/// (Android platform channels, the phone core runtime with mDNS discovery, the
/// secure-storage token store) had never been executed. This test drives
/// `AppController.init()` with `CorePlatform.phone` against stubbed platform
/// channels, so a startup failure shows up as a failing test instead of an app
/// that dies on the phone.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('twindrop-phone-');

    // Stub every channel the phone path touches. One handler per channel:
    // registering a second handler for the same channel replaces the first.
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    void stub(String channel, Map<String, Object?> replies) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        return replies[call.method];
      });
    }

    stub('twindrop/app', <String, Object?>{
      'getVersion': <String, Object?>{
        'versionName': '1.0.0',
        'versionCode': '1',
      },
      'getPlatformInfo': <String, Object?>{
        'model': 'Test Phone',
        'androidVersion': '16',
      },
      'areNotificationsEnabled': true,
      'requestNotificationPermission': false,
    });
    stub('twindrop/keepalive', <String, Object?>{
      'isRunning': false,
      'isPaused': false,
      'isBatteryOptimizationIgnored': true,
      'setStatus': true,
      'acquireMulticastLock': true,
      'releaseMulticastLock': true,
    });
    stub('twindrop/network', <String, Object?>{
      'getCurrent': <String, Object?>{'online': true, 'wifi': true},
    });
    stub('twindrop/share_queue', <String, Object?>{
      'readPending': <Object?>[],
      'consumeLaunchShareId': null,
    });
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in <String>[
      'twindrop/app',
      'twindrop/keepalive',
      'twindrop/network',
      'twindrop/share_queue',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('the phone runtime starts and opens its replica', () async {
    final runtime = await CoreRuntime.open(
      platform: CorePlatform.phone,
      deviceName: 'Test Phone',
      dataDir: tempDir.path,
      tokenStore: MemoryTokenStore(),
      logger: Logger.silent,
    );
    addTearDown(runtime.dispose);

    // The Inbox exists right after opening.
    final inbox = await runtime.notepad.ensureInbox();
    expect(inbox.id, Category.inboxId);

    // start() must not throw: it opens the connection manager, which may look
    // for a paired desktop over mDNS.
    await runtime.start();
    expect(runtime.status, isNotNull);
  });

  test('the app controller initialises for a phone', () async {
    final controller = AppController(
      paths: AppPaths(supportDir: tempDir, documentsDir: tempDir),
      platform: CorePlatform.phone,
      tokenStore: MemoryTokenStore(),
      logger: Logger.silent,
    );
    addTearDown(controller.dispose);

    await controller.init();

    // A failure during init must be reported, not thrown.
    expect(
      controller.fatalError,
      isNull,
      reason: 'init failed: ${controller.fatalError}',
    );
    expect(controller.initialized, isTrue);
    expect(controller.deviceName, 'Test Phone');
    expect(controller.categories, isNotEmpty);
    expect(controller.selectedCategoryId, Category.inboxId);
  });
}
