import 'dart:async';
import 'dart:io';

// Only the runtime option is needed; importing all of drift would clash with
// the matcher's `isNotNull`.
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';

/// End-to-end restart test (AGENTS.md, "Definition of done" #6):
/// *offline messages/shares sync exactly once after reconnect, even after
/// process restart*.
///
/// The desktop is paused (the host stops, so the phone is offline), the phone
/// writes a message, the phone's whole runtime is disposed and opened again
/// from the same data directory — a process restart — and only then does the
/// desktop come back. The message must arrive exactly once.
void main() {
  // The test deliberately opens the same database file twice, in sequence, to
  // simulate a process restart. Drift cannot tell that apart from a second
  // live connection, so the warning is turned off here.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<bool> waitUntil(
    Future<bool> Function() condition, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await condition()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return await condition();
  }

  test(
    'an offline message survives a process restart and syncs exactly once',
    () async {
      final root = await Directory.systemTemp.createTemp('twindrop-restart-');
      final deskDir = Directory('${root.path}/desk')..createSync();
      final phoneDir = Directory('${root.path}/phone')..createSync();
      // The device token lives in secure storage, which survives the restart;
      // this stand-in is shared across both "processes" for the same reason.
      final tokenStore = MemoryTokenStore();
      final log = Logger.silent;

      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });

      late CoreRuntime desk;
      CoreRuntime? phone;

      Future<CoreRuntime> openPhone() => CoreRuntime.open(
        platform: CorePlatform.phone,
        deviceName: 'Phone',
        dataDir: phoneDir.path,
        tokenStore: tokenStore,
        logger: log,
        enableDiscovery: false,
      );

      desk = await CoreRuntime.open(
        platform: CorePlatform.desktop,
        deviceName: 'Desk',
        dataDir: deskDir.path,
        sanIps: const ['127.0.0.1'],
        tokenStore: tokenStore,
        logger: log,
        enableDiscovery: false,
      );
      phone = await openPhone();

      await desk.start();
      await phone.start();

      // ---- pair -------------------------------------------------------------
      final session = await desk.startPairingSession();
      final approved = Completer<void>();
      String? deskCode;
      final requests = desk.pairingService!.requests.listen((request) async {
        if (request.state != PairingState.pendingApproval) return;
        deskCode = request.confirmationCode;
        await desk.approvePairing(request.requestId);
        if (!approved.isCompleted) approved.complete();
      });

      String? phoneCode;
      final paired = phone.pairWithQr(
        payload: session.payload.encode(),
        onCode: (code) => phoneCode = code,
      );
      await paired.timeout(const Duration(seconds: 30));
      await approved.future.timeout(const Duration(seconds: 10));
      expect(phoneCode, isNotNull);
      expect(phoneCode, deskCode);

      await waitUntil(() async {
        final d = await desk.diagnostics();
        final p = await phone!.diagnostics();
        return d.connectedPeerIds.isNotEmpty && p.connectedPeerIds.isNotEmpty;
      });
      expect((await desk.diagnostics()).connectedPeerIds, isNotEmpty);

      // ---- go offline and write a message ----------------------------------
      await desk.pause();
      final offline = await phone.chat.sendMessage('written while offline');
      expect(offline.text, 'written while offline');

      // Nothing reached the desktop yet.
      final before = await desk.chat.listMessages();
      expect(before.where((m) => m.text == 'written while offline'), isEmpty);

      // ---- process restart --------------------------------------------------
      await phone.dispose();
      phone = null;

      phone = await openPhone();
      await phone.start();

      // The queued message survived the restart in the local replica.
      final afterRestart = await phone.chat.listMessages();
      expect(
        afterRestart.where((m) => m.text == 'written while offline').length,
        1,
        reason: 'the message must still be in the replica after the restart',
      );

      // ---- reconnect --------------------------------------------------------
      await desk.resume();

      final arrived = await waitUntil(() async {
        final messages = await desk.chat.listMessages();
        return messages.any((m) => m.text == 'written while offline');
      });
      expect(
        arrived,
        isTrue,
        reason: 'the message must arrive after reconnect',
      );

      // Give the sync engine a moment to (not) deliver a second copy.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final desktopMessages = await desk.chat.listMessages();
      expect(
        desktopMessages.where((m) => m.text == 'written while offline').length,
        1,
        reason: 'the message must arrive exactly once',
      );

      final phoneMessages = await phone.chat.listMessages();
      expect(
        phoneMessages.where((m) => m.text == 'written while offline').length,
        1,
        reason: 'the local copy must not be duplicated by the sync',
      );

      await requests.cancel();
      await phone.dispose();
      await desk.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
