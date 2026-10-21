import 'dart:convert';

import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';
import 'package:twindrop_core/db/store_ops.dart';

import 'support/test_support.dart';

/// A deterministic 32-byte pairing token, base64url encoded.
String testPairingToken() =>
    base64UrlToken(List<int>.generate(32, (i) => (i * 7 + 3) % 256));

Map<String, dynamic> payloadJson({
  String app = 'twindrop',
  int version = 1,
  List<String> hosts = const ['192.168.1.10'],
  int port = 47321,
  String fingerprint =
      'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90',
  String? token,
  String exp = '2099-01-01T00:00:00.000Z',
  String name = 'Desktop',
  String id = '018f0000-0000-7000-8000-000000000abc',
}) {
  return <String, dynamic>{
    'app': app,
    'v': version,
    'hosts': hosts,
    'port': port,
    'fp': fingerprint,
    'pt': token ?? testPairingToken(),
    'exp': exp,
    'name': name,
    'id': id,
  };
}

String encodePayload(Map<String, dynamic> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

void main() {
  late AppDatabase db;
  late ChangeBus bus;
  late PeerRegistry peers;

  setUp(() {
    db = AppDatabase.memory();
    bus = ChangeBus();
    peers = PeerRegistry(db: db, bus: bus, logger: Logger.silent);
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  group('PairingPayload parsing', () {
    test('round-trips a valid payload', () {
      final payload = PairingPayload.parse(encodePayload(payloadJson()));
      expect(payload.hosts, ['192.168.1.10']);
      expect(payload.port, 47321);
      expect(payload.deviceName, 'Desktop');
      expect(payload.deviceId, '018f0000-0000-7000-8000-000000000abc');
      expect(payload.pairingTokenBytes.length, 32);
      expect(payload.isExpiredAt(DateTime.utc(2098, 12, 31)), isFalse);
      expect(payload.isExpiredAt(DateTime.utc(2100, 1, 1)), isTrue);
    });

    test('rejects an empty payload', () {
      expect(() => PairingPayload.parse(''), throwsA(isA<ProtocolError>()));
      expect(() => PairingPayload.parse('   '), throwsA(isA<ProtocolError>()));
    });

    test('rejects a payload with whitespace', () {
      final raw = encodePayload(payloadJson());
      expect(
        () => PairingPayload.parse(
          '${raw.substring(0, 10)} ${raw.substring(10)}',
        ),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('rejects a payload that is not base64url', () {
      expect(
        () => PairingPayload.parse('not base64!!!'),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('rejects a payload that is not a JSON object', () {
      final raw = base64Url.encode(utf8.encode('[1,2,3]')).replaceAll('=', '');
      expect(() => PairingPayload.parse(raw), throwsA(isA<ProtocolError>()));
    });

    test('rejects a foreign app id', () {
      final raw = encodePayload(payloadJson(app: 'otherapp'));
      expect(() => PairingPayload.parse(raw), throwsA(isA<ProtocolError>()));
    });

    test('rejects a newer protocol version with UnsupportedVersionError', () {
      final raw = encodePayload(payloadJson(version: 2));
      expect(
        () => PairingPayload.parse(raw),
        throwsA(isA<UnsupportedVersionError>()),
      );
    });

    test('rejects an older protocol version', () {
      final raw = encodePayload(payloadJson(version: 0));
      expect(() => PairingPayload.parse(raw), throwsA(isA<ProtocolError>()));
    });

    test('rejects an empty or oversized host list', () {
      expect(
        () => PairingPayload.parse(encodePayload(payloadJson(hosts: const []))),
        throwsA(isA<ProtocolError>()),
      );
      expect(
        () => PairingPayload.parse(
          encodePayload(
            payloadJson(hosts: List<String>.generate(9, (i) => '192.168.1.$i')),
          ),
        ),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('rejects a host that is not an IP address', () {
      expect(
        () => PairingPayload.parse(
          encodePayload(payloadJson(hosts: const ['desktop.local'])),
        ),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('rejects an out-of-range port', () {
      expect(
        () => PairingPayload.parse(encodePayload(payloadJson(port: 0))),
        throwsA(isA<ProtocolError>()),
      );
      expect(
        () => PairingPayload.parse(encodePayload(payloadJson(port: 70000))),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('rejects a fingerprint that is not a sha256 hex string', () {
      expect(
        () => PairingPayload.parse(
          encodePayload(payloadJson(fingerprint: 'abc')),
        ),
        throwsA(isA<ProtocolError>()),
      );
      expect(
        () => PairingPayload.parse(
          encodePayload(payloadJson(fingerprint: 'A1B2' + '0' * 60)),
        ),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('rejects a pairing token with the wrong length', () {
      final short = base64UrlToken(List<int>.generate(16, (i) => i));
      expect(
        () => PairingPayload.parse(encodePayload(payloadJson(token: short))),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('rejects a non-canonical pairing token', () {
      final canonical = testPairingToken();
      final padded = base64Url.encode(List<int>.generate(32, (i) => i));
      expect(
        () => PairingPayload.parse(encodePayload(payloadJson(token: padded))),
        throwsA(isA<ProtocolError>()),
      );
      expect(canonical.length, 43);
    });

    test('rejects a missing or invalid expiry', () {
      final json = payloadJson()..remove('exp');
      expect(
        () => PairingPayload.parse(encodePayload(json)),
        throwsA(isA<ProtocolError>()),
      );
      expect(
        () => PairingPayload.parse(encodePayload(payloadJson(exp: 'soon'))),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('rejects an empty device name', () {
      expect(
        () => PairingPayload.parse(encodePayload(payloadJson(name: '   '))),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('rejects a device id that is not a UUID', () {
      expect(
        () =>
            PairingPayload.parse(encodePayload(payloadJson(id: 'not-a-uuid'))),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('rejects an oversize payload', () {
      final raw = 'a' * (PairingPayload.maxEncodedLength + 1);
      expect(
        () => PairingPayload.parse(raw),
        throwsA(isA<PayloadTooLargeError>()),
      );
    });
  });

  group('confirmation code', () {
    test('is identical on both sides for the same inputs', () {
      final bytes = List<int>.generate(32, (i) => i);
      final a = confirmationCode(
        pairingTokenBytes: bytes,
        requestId: 'request-1',
        fingerprintHex: 'ab' * 32,
      );
      final b = confirmationCode(
        pairingTokenBytes: bytes,
        requestId: 'request-1',
        fingerprintHex: 'ab' * 32,
      );
      expect(a, b);
      expect(a.length, 4);
      expect(a, matches(RegExp(r'^[0-9]{4}$')));
    });

    test('changes with the request id and with the fingerprint', () {
      final bytes = List<int>.generate(32, (i) => i);
      final base = confirmationCode(
        pairingTokenBytes: bytes,
        requestId: 'request-1',
        fingerprintHex: 'ab' * 32,
      );
      final other = confirmationCode(
        pairingTokenBytes: bytes,
        requestId: 'request-2',
        fingerprintHex: 'ab' * 32,
      );
      expect(other, isNot(base));
      final otherFp = confirmationCode(
        pairingTokenBytes: bytes,
        requestId: 'request-1',
        fingerprintHex: 'cd' * 32,
      );
      expect(otherFp, isNot(base));
    });

    test('is zero padded to four digits', () {
      final bytes = List<int>.generate(32, (i) => i);
      final code = confirmationCode(
        pairingTokenBytes: bytes,
        requestId: 'r',
        fingerprintHex: 'ab' * 32,
      );
      expect(code.length, 4);
      expect(int.parse(code), greaterThanOrEqualTo(0));
      expect(int.parse(code), lessThan(10000));
    });
  });

  group('manual pairing code', () {
    test('encodes 8 groups of 4 base32 characters', () {
      final bytes = List<int>.generate(32, (i) => i);
      final code = ManualPairingCode.encode(bytes);
      expect(code.split(' ').length, 8);
      expect(code.replaceAll(' ', '').length, 32);
      expect(code, matches(RegExp(r'^[A-Z2-7]{4}( [A-Z2-7]{4}){7}$')));
    });

    test('decodes back to the first 20 bytes', () {
      final bytes = List<int>.generate(32, (i) => i);
      final code = ManualPairingCode.encode(bytes);
      final decoded = ManualPairingCode.decode(code);
      expect(decoded, isNotNull);
      expect(decoded!.length, 20);
      expect(decoded, bytes.sublist(0, 20));
    });

    test('ignores case and separators', () {
      final bytes = List<int>.generate(32, (i) => i);
      final code = ManualPairingCode.encode(bytes);
      expect(
        ManualPairingCode.decode(code.toLowerCase()),
        ManualPairingCode.decode(code.replaceAll(' ', '-')),
      );
    });

    test('rejects a code of the wrong length or with invalid characters', () {
      expect(ManualPairingCode.decode('ABCD'), isNull);
      expect(
        ManualPairingCode.decode('ABCD EFGH IJKL MNOP QRST UVWX YZ01 2345'),
        isNull,
      );
    });
  });

  group('PairingService', () {
    late DateTime now;
    late PairingService pairing;

    setUp(() {
      now = DateTime.utc(2026, 1, 1, 12);
      pairing = PairingService(
        peers: peers,
        logger: Logger.silent,
        hostDeviceId: 'desktop-device',
        hostName: 'Desktop',
        fingerprint: 'ab' * 32,
        hostsProvider: () => const ['192.168.1.10'],
        portProvider: () => 47321,
        now: () => now,
      );
    });

    PairRequest requestWith(String token, {String? clientId}) => PairRequest(
      pairingToken: token,
      clientInstanceId: clientId ?? testUuid(1),
      displayName: 'Phone',
      platform: 'android',
      protocolVersion: FrameCodec.protocolVersion,
    );

    test('a session lasts five minutes', () {
      final session = pairing.startSession();
      expect(pairing.isOpen, isTrue);
      expect(session.expiresAt.difference(session.startedAt).inMinutes, 5);
      expect(session.isExpiredAt(now.add(const Duration(minutes: 4))), isFalse);
      expect(session.isExpiredAt(now.add(const Duration(minutes: 6))), isTrue);
    });

    test('an expired session is closed', () {
      pairing.startSession();
      now = now.add(const Duration(minutes: 6));
      expect(pairing.currentSession, isNull);
      expect(pairing.isOpen, isFalse);
    });

    test('a request with a wrong token is rejected', () async {
      final session = pairing.startSession();
      await expectLater(
        pairing.handleRequest(requestWith('wrong-token-value')),
        throwsA(isA<PairingFailedError>()),
      );
      expect(pairing.pendingRequests, isEmpty);
      expect(session.payload.pairingToken, isNot('wrong-token-value'));
    });

    test('a valid request is accepted and needs an approval', () async {
      final session = pairing.startSession();
      final response = await pairing.handleRequest(
        requestWith(session.payload.pairingToken),
      );
      expect(response.requestId, isNotEmpty);
      expect(response.pollSecret, isNotEmpty);

      expect(pairing.pendingRequests.length, 1);
      final info = pairing.pendingRequests.first;
      expect(info.displayName, 'Phone');
      expect(info.confirmationCode.length, 4);
      expect(info.state, PairingState.pendingApproval);

      // Before the approval the status poll carries no token.
      final status = pairing.status(response.requestId, response.pollSecret);
      expect(status.state, PairingState.pendingApproval);
      expect(status.deviceToken, isNull);
    });

    test('the confirmation code is the same on both sides', () async {
      final session = pairing.startSession();
      final response = await pairing.handleRequest(
        requestWith(session.payload.pairingToken),
      );
      final desktopCode = pairing.pendingRequests.first.confirmationCode;
      final phoneCode = confirmationCode(
        pairingTokenBytes: session.payload.pairingTokenBytes,
        requestId: response.requestId,
        fingerprintHex: 'ab' * 32,
      );
      expect(desktopCode, phoneCode);
    });

    test('approval creates a peer that stores only the token hash', () async {
      final session = pairing.startSession();
      final response = await pairing.handleRequest(
        requestWith(session.payload.pairingToken),
      );
      final peer = await pairing.approve(response.requestId);
      expect(peer.tokenHash, isNotNull);
      expect(peer.tokenHash!.length, 64);
      expect(peer.kind, PeerKind.phone);
      expect(peer.isRevoked, isFalse);

      final stored = await db.peerById(peer.id);
      expect(stored!.tokenHash, peer.tokenHash);
    });

    test('the device token is handed out exactly once', () async {
      final session = pairing.startSession();
      final response = await pairing.handleRequest(
        requestWith(session.payload.pairingToken),
      );
      await pairing.approve(response.requestId);

      final first = pairing.status(response.requestId, response.pollSecret);
      expect(first.state, PairingState.approved);
      expect(first.deviceToken, isNotNull);
      expect(first.deviceToken!.length, greaterThanOrEqualTo(40));

      final second = pairing.status(response.requestId, response.pollSecret);
      expect(second.deviceToken, isNull);
      expect(second.alreadyCollected, isTrue);
    });

    test('a wrong poll secret is rejected', () async {
      final session = pairing.startSession();
      final response = await pairing.handleRequest(
        requestWith(session.payload.pairingToken),
      );
      await pairing.approve(response.requestId);
      expect(
        () => pairing.status(response.requestId, 'wrong-secret'),
        throwsA(isA<PairingFailedError>()),
      );
    });

    test('the pairing token is single use', () async {
      final session = pairing.startSession();
      final response = await pairing.handleRequest(
        requestWith(session.payload.pairingToken),
      );
      await pairing.approve(response.requestId);

      // The session is closed after the approval.
      expect(pairing.isOpen, isFalse);
      await expectLater(
        pairing.handleRequest(requestWith(session.payload.pairingToken)),
        throwsA(isA<PairingFailedError>()),
      );
    });

    test('the same client polling twice gets the same request', () async {
      final session = pairing.startSession();
      final first = await pairing.handleRequest(
        requestWith(session.payload.pairingToken),
      );
      final second = await pairing.handleRequest(
        requestWith(session.payload.pairingToken),
      );
      expect(second.requestId, first.requestId);
      expect(second.pollSecret, first.pollSecret);
      expect(pairing.pendingRequests.length, 1);
    });

    test('a rejected request never hands out a token', () async {
      final session = pairing.startSession();
      final response = await pairing.handleRequest(
        requestWith(session.payload.pairingToken),
      );
      await pairing.reject(response.requestId);
      final status = pairing.status(response.requestId, response.pollSecret);
      expect(status.state, PairingState.rejected);
      expect(status.deviceToken, isNull);
      expect(await peers.list(), isEmpty);
    });

    test('the manual code verifies against the session token', () {
      final session = pairing.startSession(manual: true);
      expect(pairing.verifyManualCode(session.manualCode), isTrue);
      expect(
        pairing.verifyManualCode('ABCD EFGH IJKL MNOP QRST UVWX YZ12 3456'),
        isFalse,
      );
      expect(pairing.verifyManualCode('nonsense'), isFalse);
    });
  });

  group('pairing rate limiting', () {
    test('locks out after five failed attempts', () async {
      final pairing = PairingService(
        peers: peers,
        logger: Logger.silent,
        hostDeviceId: 'desktop-device',
        hostName: 'Desktop',
        fingerprint: 'ab' * 32,
        hostsProvider: () => const ['192.168.1.10'],
        portProvider: () => 47321,
      );
      pairing.startSession();

      for (var i = 0; i < 5; i++) {
        await expectLater(
          pairing.handleRequest(
            PairRequest(
              pairingToken: 'wrong-token-value-$i',
              clientInstanceId: testUuid(1),
              displayName: 'Phone',
              platform: 'android',
              protocolVersion: FrameCodec.protocolVersion,
            ),
          ),
          throwsA(isA<PairingFailedError>()),
        );
      }

      await expectLater(
        pairing.handleRequest(
          PairRequest(
            pairingToken: 'wrong-token-value-6',
            clientInstanceId: 'client-1',
            displayName: 'Phone',
            platform: 'android',
            protocolVersion: FrameCodec.protocolVersion,
          ),
        ),
        throwsA(isA<RateLimitedError>()),
      );
    });

    test('the lockout expires', () {
      var now = DateTime.utc(2026, 1, 1, 12);
      final limiter = PairingRateLimiter(now: () => now);
      for (var i = 0; i < 5; i++) {
        limiter.recordFailure();
      }
      expect(limiter.isLocked, isTrue);
      expect(limiter.remaining.inSeconds, 60);
      now = now.add(const Duration(seconds: 61));
      expect(limiter.isLocked, isFalse);
    });

    test('a successful attempt clears the failure counter', () {
      final limiter = PairingRateLimiter();
      for (var i = 0; i < 4; i++) {
        limiter.recordFailure();
      }
      limiter.recordSuccess();
      expect(limiter.isLocked, isFalse);
      limiter.recordFailure();
      expect(limiter.isLocked, isFalse);
    });
  });
}
