import 'dart:io';

import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';

void main() {
  late Directory desktopDir;
  late Directory phoneDir;

  setUp(() async {
    desktopDir = await Directory.systemTemp.createTemp('twindrop_rt_desktop_');
    phoneDir = await Directory.systemTemp.createTemp('twindrop_rt_phone_');
  });

  tearDown(() async {
    if (desktopDir.existsSync()) await desktopDir.delete(recursive: true);
    if (phoneDir.existsSync()) await phoneDir.delete(recursive: true);
  });

  Future<CoreRuntime> openDesktop() async {
    final runtime = await CoreRuntime.open(
      platform: CorePlatform.desktop,
      deviceName: 'Desktop',
      dataDir: desktopDir.path,
      sanIps: const ['127.0.0.1'],
      enableDiscovery: false,
      inMemory: true,
      logger: Logger.silent,
      deviceId: '018f0000-0000-7000-8000-00000000d001',
    );
    addTearDown(runtime.dispose);
    return runtime;
  }

  Future<CoreRuntime> openPhone() async {
    final runtime = await CoreRuntime.open(
      platform: CorePlatform.phone,
      deviceName: 'Phone',
      dataDir: phoneDir.path,
      enableDiscovery: false,
      inMemory: true,
      logger: Logger.silent,
      deviceId: '018f0000-0000-7000-8000-00000000d002',
    );
    addTearDown(runtime.dispose);
    return runtime;
  }

  group('desktop pairing session', () {
    test('opens a session, serves the QR payload and closes again', () async {
      final runtime = await openDesktop();
      final session = await runtime.startPairingSession();

      expect(runtime.host!.isRunning, isTrue);
      expect(runtime.status, ConnectionStatus.pairing);
      expect(session.payload.fingerprint, runtime.identity!.fingerprint);
      expect(session.payload.hosts, contains('127.0.0.1'));
      expect(session.payload.port, runtime.host!.port);

      // The payload survives the QR round trip.
      final parsed = PairingPayload.parse(session.payload.encode());
      expect(parsed.fingerprint, session.payload.fingerprint);
      expect(parsed.port, session.payload.port);
      expect(parsed.pairingToken, session.payload.pairingToken);

      await runtime.cancelPairingSession();
      expect(runtime.host!.isRunning, isFalse);
      expect(runtime.status, ConnectionStatus.unpaired);
    });

    test('the manual probe returns the short fingerprint', () async {
      final runtime = await openDesktop();
      await runtime.startPairingSession();
      final probe = await runtime.manualProbe('127.0.0.1', runtime.host!.port);
      expect(probe.fingerprint, runtime.identity!.fingerprint);
      expect(probe.shortFingerprint, runtime.identity!.shortFingerprint);
    });

    test('probeManual returns only the short fingerprint', () async {
      final runtime = await openDesktop();
      await runtime.startPairingSession();
      final short = await runtime.probeManual('127.0.0.1', runtime.host!.port);
      expect(short, runtime.identity!.shortFingerprint);
    });
  });

  group('phone pairs with the desktop', () {
    test('the QR payload completes the pairing and stores the pin', () async {
      final desktop = await openDesktop();
      final phone = await openPhone();

      final session = await desktop.startPairingSession();
      final qr = session.payload.encode();

      final codes = <String>[];
      final pending = desktop.pairingService!.requests.firstWhere(
        (info) => info.state == PairingState.pendingApproval,
      );

      final pairing = phone.pairWithQr(payload: qr, onCode: codes.add);

      final request = await pending.timeout(const Duration(seconds: 15));
      final peer = await desktop.approvePairing(request.requestId);
      expect(peer.id, phone.deviceId);

      final result = await pairing.timeout(const Duration(seconds: 25));
      expect(result.deviceToken, isNotEmpty);
      expect(result.fingerprint, desktop.identity!.fingerprint);
      expect(result.host, '127.0.0.1');
      expect(result.port, desktop.host!.port);
      expect(codes.single.length, 4);
      expect(codes.single, request.confirmationCode);

      // The phone stored the pin and the token, but never the raw token in
      // the database.
      final stored = await phone.peers.get(desktop.deviceId);
      expect(stored, isNotNull);
      expect(stored!.certFp, desktop.identity!.fingerprint);
      expect(stored.tokenRef, peerTokenRef(desktop.deviceId));
      expect(stored.tokenHash, isNull);
      final token = await phone.tokenStore.read(peerTokenRef(desktop.deviceId));
      expect(token, result.deviceToken);

      // The desktop stores only the hash of the phone's token.
      final desktopPeer = await desktop.peers.get(phone.deviceId);
      expect(desktopPeer!.tokenHash, DeviceTokens.hash(result.deviceToken));
    });

    test('the phone can unpair again', () async {
      final desktop = await openDesktop();
      final phone = await openPhone();

      final session = await desktop.startPairingSession();
      final pending = desktop.pairingService!.requests.firstWhere(
        (info) => info.state == PairingState.pendingApproval,
      );
      final pairing = phone.pairWithQr(
        payload: session.payload.encode(),
        onCode: (_) {},
      );
      final request = await pending.timeout(const Duration(seconds: 15));
      await desktop.approvePairing(request.requestId);
      await pairing.timeout(const Duration(seconds: 25));

      expect((await phone.peers.active()).length, 1);
      await phone.unpair();
      expect((await phone.peers.list()).length, 0);
      expect(
        await phone.tokenStore.read(peerTokenRef(desktop.deviceId)),
        isNull,
        reason: 'the token is deleted from the secure store',
      );
      expect(phone.status, ConnectionStatus.unpaired);
    });

    test('an expired QR payload is refused', () async {
      final phone = await openPhone();
      final expired = PairingPayload(
        hosts: const ['127.0.0.1'],
        port: 47321,
        fingerprint: 'a' * 64,
        pairingToken: base64UrlToken(List<int>.generate(32, (i) => i)),
        expiresAt: DateTime.utc(2020, 1, 1),
        deviceName: 'Desktop',
        deviceId: '018f0000-0000-7000-8000-000000000abc',
      );
      await expectLater(
        phone.pairWithQr(payload: expired.encode(), onCode: (_) {}),
        throwsA(isA<PairingFailedError>()),
      );
    });

    test('a malformed QR payload is refused', () async {
      final phone = await openPhone();
      await expectLater(
        phone.pairWithQr(payload: 'not a pairing payload', onCode: (_) {}),
        throwsA(isA<ProtocolError>()),
      );
    });
  });
}
