import 'dart:io';

import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';
import 'package:twindrop_core/db/store_ops.dart';

import 'support/test_support.dart';

void main() {
  late AppDatabase db;
  late ChangeBus bus;
  late PeerRegistry peers;
  late HlcClock clock;
  late MergeEngine merge;
  late SyncEngine sync;
  late Directory tlsDir;
  late TlsIdentity identity;
  late HostServer host;

  setUp(() async {
    db = AppDatabase.memory();
    bus = ChangeBus();
    peers = PeerRegistry(db: db, bus: bus, logger: Logger.silent);
    clock = HlcClock(deviceId: 'desktop', nowMs: () => 1000);
    merge = MergeEngine(db: db, clock: clock, logger: Logger.silent);
    sync = SyncEngine(
      db: db,
      merge: merge,
      clock: clock,
      bus: bus,
      logger: Logger.silent,
    );
    tlsDir = await Directory.systemTemp.createTemp('twindrop_pairclient_');
    identity = await TlsIdentity.loadOrCreate(
      tlsDir,
      sanIps: const ['127.0.0.1'],
    );
    host = HostServer(
      identity: identity,
      db: db,
      sync: sync,
      bus: bus,
      peers: peers,
      logger: Logger.silent,
      deviceId: 'desktop-device',
      deviceName: 'Desktop',
      appVersion: '0.1.0',
      versionName: () => '0.1.0',
      localHosts: () => const ['127.0.0.1'],
      preferredPort: 0,
    );
    await host.start();
  });

  tearDown(() async {
    await host.dispose();
    await db.close();
    await bus.dispose();
    if (tlsDir.existsSync()) await tlsDir.delete(recursive: true);
  });

  group('PairingClient.pairWithPayload', () {
    test(
      'pairs with an approved request and returns the device token',
      () async {
        final session = host.pairing.startSession();
        final client = PairingClient(
          logger: Logger.silent,
          pollTimeout: const Duration(seconds: 20),
        );
        final codes = <String>[];

        final pending = host.pairing.requests.firstWhere(
          (info) => info.state == PairingState.pendingApproval,
        );

        final future = client.pairWithPayload(
          payload: session.payload,
          clientDeviceId: testUuid(1),
          displayName: 'Phone',
          platform: 'android',
          onCode: codes.add,
        );

        final request = await pending.timeout(const Duration(seconds: 15));
        await host.pairing.approve(request.requestId);

        final result = await future.timeout(const Duration(seconds: 25));
        expect(result.deviceToken, isNotEmpty);
        expect(result.deviceToken.length, greaterThanOrEqualTo(40));
        expect(result.fingerprint, identity.fingerprint);
        expect(result.hostDeviceId, 'desktop-device');
        expect(result.hostName, 'Desktop');
        expect(result.deviceId, testUuid(1));
        expect(result.host, '127.0.0.1');
        expect(result.port, host.port);

        // The phone shows the same 4-digit code as the desktop.
        expect(codes.length, 1);
        expect(codes.single.length, 4);
        expect(codes.single, request.confirmationCode);

        // The desktop stores only the hash of the token.
        final peer = await db.peerById(testUuid(1));
        expect(peer, isNotNull);
        expect(peer!.tokenHash, DeviceTokens.hash(result.deviceToken));
        expect(peer.tokenHash, isNot(result.deviceToken));
      },
    );

    test('an expired payload is refused before any request', () async {
      final session = host.pairing.startSession();
      final client = PairingClient(logger: Logger.silent);
      await expectLater(
        client.pairWithPayload(
          payload: session.payload,
          clientDeviceId: testUuid(2),
          displayName: 'Phone',
          platform: 'android',
          onCode: (_) {},
          now: () => DateTime.utc(2100, 1, 1),
        ),
        throwsA(isA<PairingFailedError>()),
      );
    });

    test('an unreachable desktop reports a network error', () async {
      final session = host.pairing.startSession();
      final client = PairingClient(
        logger: Logger.silent,
        pollTimeout: const Duration(seconds: 2),
      );
      final payload = PairingPayload(
        hosts: const ['127.0.0.1'],
        port: 1, // nothing listens there
        fingerprint: identity.fingerprint,
        pairingToken: session.payload.pairingToken,
        expiresAt: DateTime.utc(2099, 1, 1),
        deviceName: 'Desktop',
        deviceId: 'desktop-device',
      );
      await expectLater(
        client.pairWithPayload(
          payload: payload,
          clientDeviceId: testUuid(3),
          displayName: 'Phone',
          platform: 'android',
          onCode: (_) {},
        ),
        throwsA(isA<NetworkError>()),
      );
    });

    test('a rejected request fails the pairing', () async {
      final session = host.pairing.startSession();
      final client = PairingClient(
        logger: Logger.silent,
        pollTimeout: const Duration(seconds: 20),
      );
      final pending = host.pairing.requests.firstWhere(
        (info) => info.state == PairingState.pendingApproval,
      );

      final future = client.pairWithPayload(
        payload: session.payload,
        clientDeviceId: testUuid(4),
        displayName: 'Phone',
        platform: 'android',
        onCode: (_) {},
      );

      final request = await pending.timeout(const Duration(seconds: 15));
      await host.pairing.reject(request.requestId);

      await expectLater(
        future.timeout(const Duration(seconds: 25)),
        throwsA(isA<PairingFailedError>()),
      );
    });
  });

  group('PairingClient.probeManual', () {
    test('returns the fingerprint of the desktop certificate', () async {
      final client = PairingClient(logger: Logger.silent);
      final probe = await client.probeManual('127.0.0.1', host.port);
      expect(probe.fingerprint, identity.fingerprint);
      expect(probe.shortFingerprint, identity.shortFingerprint);
      expect(probe.shortFingerprint.length, 6);
      expect(probe.host, '127.0.0.1');
      expect(probe.port, host.port);
    });

    test('fails when nothing answers', () async {
      final client = PairingClient(logger: Logger.silent);
      await expectLater(
        client.probeManual('127.0.0.1', 1),
        throwsA(isA<NetworkError>()),
      );
    });
  });

  group('PairingClient.pairManually', () {
    test('pairs with the typed code', () async {
      final session = host.pairing.startSession(manual: true);
      final client = PairingClient(
        logger: Logger.silent,
        pollTimeout: const Duration(seconds: 20),
      );
      final probe = await client.probeManual('127.0.0.1', host.port);
      expect(probe.fingerprint, identity.fingerprint);

      final pending = host.pairing.requests.firstWhere(
        (info) => info.state == PairingState.pendingApproval,
      );

      final future = client.pairManually(
        probe: probe,
        code: session.manualCode,
        clientDeviceId: testUuid(5),
        displayName: 'Phone',
        platform: 'android',
        onCode: (_) {},
      );

      final request = await pending.timeout(const Duration(seconds: 15));
      await host.pairing.approve(request.requestId);

      final result = await future.timeout(const Duration(seconds: 25));
      expect(result.deviceToken, isNotEmpty);
    });

    test('rejects an invalid code', () async {
      final client = PairingClient(logger: Logger.silent);
      final probe = await client.probeManual('127.0.0.1', host.port);
      await expectLater(
        client.pairManually(
          probe: probe,
          code: 'nonsense',
          clientDeviceId: testUuid(6),
          displayName: 'Phone',
          platform: 'android',
          onCode: (_) {},
        ),
        throwsA(isA<ValidationError>()),
      );
    });
  });
}
