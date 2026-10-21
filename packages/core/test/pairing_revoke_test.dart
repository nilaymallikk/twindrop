import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';
import 'package:twindrop_core/db/store_ops.dart';

import 'support/test_support.dart';

void main() {
  late AppDatabase db;
  late ChangeBus bus;
  late PeerRegistry peers;
  late TokenAuthenticator auth;

  const peerId = '018f0000-0000-7000-8000-00000000dead';
  const token = 'ZG9uZS10ZXN0LXRva2VuLXZhbHVlLTEyMzQ1Njc4OTA';

  setUp(() async {
    db = AppDatabase.memory();
    bus = ChangeBus();
    peers = PeerRegistry(db: db, bus: bus, logger: Logger.silent);
    auth = TokenAuthenticator(peers: peers, logger: Logger.silent);
  });

  tearDown(() async {
    await db.close();
    await bus.dispose();
  });

  group('device tokens', () {
    test('issues a 256-bit base64url token', () {
      final issued = DeviceTokens.issue();
      expect(issued.length, greaterThanOrEqualTo(40));
      expect(issued, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(DeviceTokens.issue(), isNot(issued));
    });

    test('stores only the sha256 hash, never the token itself', () async {
      await peers.addPairedPeer(
        makePeer(id: peerId, tokenHash: DeviceTokens.hash(token)),
      );
      final stored = await db.peerById(peerId);
      expect(stored!.tokenHash, isNotNull);
      expect(stored.tokenHash, isNot(token));
      expect(stored.tokenHash, DeviceTokens.hash(token));
      expect(stored.tokenHash!.length, 64);
      expect(DeviceTokens.hash(token), tokenHashOf(token));
    });

    test('constantTimeEquals compares exactly', () {
      expect(DeviceTokens.constantTimeEquals('abc', 'abc'), isTrue);
      expect(DeviceTokens.constantTimeEquals('abc', 'abd'), isFalse);
      expect(DeviceTokens.constantTimeEquals('abc', 'abcd'), isFalse);
      expect(DeviceTokens.constantTimeEquals('', ''), isTrue);
    });
  });

  group('TokenAuthenticator', () {
    test('rejects a missing Authorization header', () async {
      await expectLater(
        auth.authenticateHeader(null),
        throwsA(isA<UnauthorizedError>()),
      );
      expect(
        (await _catchError(() => auth.authenticateHeader(null))).httpStatus,
        401,
      );
    });

    test('rejects a malformed Authorization header', () async {
      for (final header in <String>[
        '',
        'Bearer',
        'Bearer ',
        'Basic $token',
        'Bearer short',
        'token $token',
      ]) {
        await expectLater(
          auth.authenticateHeader(header),
          throwsA(isA<UnauthorizedError>()),
          reason: 'header: "$header"',
        );
      }
    });

    test('rejects an unknown token', () async {
      await expectLater(
        auth.authenticateToken('some-other-token-that-is-long-enough'),
        throwsA(isA<UnauthorizedError>()),
      );
    });

    test('accepts a valid token and resolves the peer identity', () async {
      await peers.addPairedPeer(
        makePeer(id: peerId, tokenHash: DeviceTokens.hash(token)),
      );
      final peer = await auth.authenticateToken(token);
      expect(peer.id, peerId);
      expect(peer.isRevoked, isFalse);
    });

    test(
      'resolves the identity from the token, not from a claimed id',
      () async {
        await peers.addPairedPeer(
          makePeer(id: peerId, tokenHash: DeviceTokens.hash(token)),
        );
        final peer = await auth.authenticateHeader('Bearer $token');
        expect(peer.id, peerId);
      },
    );
  });

  group('revocation', () {
    test('a revoked token no longer authenticates', () async {
      await peers.addPairedPeer(
        makePeer(id: peerId, tokenHash: DeviceTokens.hash(token)),
      );
      expect((await auth.authenticateToken(token)).id, peerId);

      final revoked = await peers.revoke(peerId);
      expect(revoked, isNotNull);
      expect(revoked!.isRevoked, isTrue);
      expect(revoked.revokedAt, isNotNull);

      await expectLater(
        auth.authenticateToken(token),
        throwsA(isA<TwinDropError>()),
        reason: 'a revoked device must never authenticate again',
      );
      final error = await _catchError(() => auth.authenticateToken(token));
      expect(
        error.httpStatus,
        403,
        reason: 'a revoked device is forbidden (4403 on the socket)',
      );
      expect(error, isA<ForbiddenError>());
    });

    test('a revoked peer is excluded from the active list', () async {
      await peers.addPairedPeer(
        makePeer(id: peerId, tokenHash: DeviceTokens.hash(token)),
      );
      expect((await peers.active()).length, 1);
      await peers.revoke(peerId);
      expect((await peers.active()).length, 0);
      expect(
        (await peers.list()).length,
        1,
        reason: 'the row is kept for the diagnostics screen',
      );
    });

    test(
      'revocation emits the peer id so live sockets can be closed',
      () async {
        final emitted = <String>[];
        final sub = peers.revokedStream.listen(emitted.add);
        addTearDown(sub.cancel);
        await peers.addPairedPeer(
          makePeer(id: peerId, tokenHash: DeviceTokens.hash(token)),
        );
        await peers.revoke(peerId);
        await Future<void>.delayed(Duration.zero);
        expect(emitted, contains(peerId));
      },
    );

    test('revoking an unknown peer is a no-op', () async {
      expect(await peers.revoke('does-not-exist'), isNull);
    });
  });

  group('host auth middleware over loopback TLS', () {
    late Directory tlsDir;
    late TlsIdentity identity;
    late HostServer host;
    late SyncEngine sync;
    late MergeEngine merge;

    setUp(() async {
      tlsDir = await Directory.systemTemp.createTemp('twindrop_auth_test_');
      identity = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      final clock = HlcClock(deviceId: 'desktop', nowMs: () => 1000);
      merge = MergeEngine(db: db, clock: clock, logger: Logger.silent);
      sync = SyncEngine(
        db: db,
        merge: merge,
        clock: clock,
        bus: bus,
        logger: Logger.silent,
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
      if (tlsDir.existsSync()) await tlsDir.delete(recursive: true);
    });

    Future<int> statusOf(
      String path, {
      String? bearer,
      String method = 'GET',
    }) async {
      final client = TlsIdentity.pinnedHttpClient(
        identity.fingerprint,
        timeout: const Duration(seconds: 5),
      );
      try {
        final uri = Uri.parse('https://127.0.0.1:${host.port}$path');
        final request = method == 'POST'
            ? await client.postUrl(uri).timeout(const Duration(seconds: 10))
            : await client.getUrl(uri).timeout(const Duration(seconds: 10));
        if (bearer != null) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $bearer',
          );
        }
        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        await response.drain<void>();
        return response.statusCode;
      } finally {
        client.close(force: true);
      }
    }

    test('a missing token is rejected with 401', () async {
      expect(await statusOf('/v1/devices/self/revoke', method: 'POST'), 401);
    });

    test('an unknown token is rejected with 401', () async {
      expect(
        await statusOf(
          '/v1/devices/self/revoke',
          method: 'POST',
          bearer: 'unknown-token-value-1234567890',
        ),
        401,
      );
    });

    test('a revoked token is rejected with 403', () async {
      await peers.addPairedPeer(
        makePeer(
          id: peerId,
          tokenHash: DeviceTokens.hash(token),
          certFp: identity.fingerprint,
        ),
      );
      await peers.revoke(peerId);
      expect(
        await statusOf(
          '/v1/devices/self/revoke',
          method: 'POST',
          bearer: token,
        ),
        403,
      );
    });

    test('a valid token passes the auth check', () async {
      await peers.addPairedPeer(
        makePeer(
          id: peerId,
          tokenHash: DeviceTokens.hash(token),
          certFp: identity.fingerprint,
        ),
      );
      expect(
        await statusOf(
          '/v1/devices/self/revoke',
          method: 'POST',
          bearer: token,
        ),
        200,
      );
    });

    test('the health endpoint stays reachable without a token', () async {
      expect(await statusOf('/v1/health'), 200);
    });

    test('a device can revoke itself and the token dies immediately', () async {
      await peers.addPairedPeer(
        makePeer(
          id: peerId,
          tokenHash: DeviceTokens.hash(token),
          certFp: identity.fingerprint,
        ),
      );
      expect(
        await statusOf(
          '/v1/devices/self/revoke',
          method: 'POST',
          bearer: token,
        ),
        200,
      );

      final peer = await db.peerById(peerId);
      expect(peer!.isRevoked, isTrue);
      expect(
        await statusOf(
          '/v1/devices/self/revoke',
          method: 'POST',
          bearer: token,
        ),
        403,
        reason: 'the old token must be dead right after the revoke',
      );
    });

    test('an unknown endpoint answers 404', () async {
      expect(await statusOf('/v1/nope'), 404);
    });

    test('the error body uses the documented error envelope', () async {
      final client = TlsIdentity.pinnedHttpClient(
        identity.fingerprint,
        timeout: const Duration(seconds: 5),
      );
      try {
        final request = await client
            .postUrl(
              Uri.parse(
                'https://127.0.0.1:${host.port}/v1/devices/self/revoke',
              ),
            )
            .timeout(const Duration(seconds: 10));
        final response = await request.close().timeout(
          const Duration(seconds: 10),
        );
        final body = await response.transform(utf8.decoder).join();
        expect(response.statusCode, 401);
        final decoded = jsonDecode(body) as Map<String, dynamic>;
        final error = ApiError.fromJson(decoded);
        expect(error.code, ErrorCodes.unauthorized);
        expect(error.message, isNotEmpty);
        expect(
          error.message.toLowerCase(),
          isNot(contains(token)),
          reason: 'the error body must never echo the token',
        );
      } finally {
        client.close(force: true);
      }
    });

    test('a valid token opens an authenticated WebSocket session', () async {
      await peers.addPairedPeer(
        makePeer(
          id: peerId,
          tokenHash: DeviceTokens.hash(token),
          certFp: identity.fingerprint,
        ),
      );
      final client = TlsIdentity.pinnedHttpClient(
        identity.fingerprint,
        timeout: const Duration(seconds: 5),
      );
      addTearDown(() => client.close(force: true));

      final socket = await WebSocket.connect(
        'wss://127.0.0.1:${host.port}/v1/ws',
        customClient: client,
        headers: <String, dynamic>{
          HttpHeaders.authorizationHeader: 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));
      addTearDown(() => socket.close());

      final ready = Completer<Frame>();
      socket.listen((data) {
        final frame = FrameCodec.decode(data as String);
        if (frame is ReadyFrame && !ready.isCompleted) ready.complete(frame);
      });
      socket.add(
        FrameCodec.encode(
          HelloFrame(
            deviceId: peerId,
            name: 'Phone',
            kind: PeerKind.phone,
            appVersion: '0.1.0',
          ),
        ),
      );

      final frame = await ready.future.timeout(const Duration(seconds: 10));
      expect(frame, isA<ReadyFrame>());
      expect((frame as ReadyFrame).deviceId, 'desktop-device');
    });

    test('a revoked token cannot open a WebSocket session', () async {
      await peers.addPairedPeer(
        makePeer(
          id: peerId,
          tokenHash: DeviceTokens.hash(token),
          certFp: identity.fingerprint,
        ),
      );
      await peers.revoke(peerId);

      final client = TlsIdentity.pinnedHttpClient(
        identity.fingerprint,
        timeout: const Duration(seconds: 5),
      );
      addTearDown(() => client.close(force: true));

      await expectLater(
        WebSocket.connect(
          'wss://127.0.0.1:${host.port}/v1/ws',
          customClient: client,
          headers: <String, dynamic>{
            HttpHeaders.authorizationHeader: 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 10)),
        throwsA(isA<WebSocketException>()),
        reason: 'a revoked device must not get a session',
      );
    });

    test('a missing token cannot open a WebSocket session', () async {
      final client = TlsIdentity.pinnedHttpClient(
        identity.fingerprint,
        timeout: const Duration(seconds: 5),
      );
      addTearDown(() => client.close(force: true));

      await expectLater(
        WebSocket.connect(
          'wss://127.0.0.1:${host.port}/v1/ws',
          customClient: client,
        ).timeout(const Duration(seconds: 10)),
        throwsA(isA<WebSocketException>()),
      );
    });

    test('revocation closes the live socket with 4403', () async {
      await peers.addPairedPeer(
        makePeer(
          id: peerId,
          tokenHash: DeviceTokens.hash(token),
          certFp: identity.fingerprint,
        ),
      );
      final client = TlsIdentity.pinnedHttpClient(
        identity.fingerprint,
        timeout: const Duration(seconds: 5),
      );
      addTearDown(() => client.close(force: true));

      final socket = await WebSocket.connect(
        'wss://127.0.0.1:${host.port}/v1/ws',
        customClient: client,
        headers: <String, dynamic>{
          HttpHeaders.authorizationHeader: 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 10));
      addTearDown(() => socket.close());

      final ready = Completer<Frame>();
      final closed = Completer<void>();
      socket.listen(
        (data) {
          final frame = FrameCodec.decode(data as String);
          if (frame is ReadyFrame && !ready.isCompleted) ready.complete(frame);
        },
        onDone: () {
          if (!closed.isCompleted) closed.complete();
        },
        onError: (Object _) {
          if (!closed.isCompleted) closed.complete();
        },
      );
      socket.add(
        FrameCodec.encode(
          HelloFrame(
            deviceId: peerId,
            name: 'Phone',
            kind: PeerKind.phone,
            appVersion: '0.1.0',
          ),
        ),
      );
      await ready.future.timeout(const Duration(seconds: 10));

      await peers.revoke(peerId);

      // docs/08: "Revocation closes live sockets (4403)".
      await closed.future.timeout(const Duration(seconds: 5));
      expect(socket.closeCode, CloseCodes.forbidden);
      expect(socket.closeCode, 4403);
      expect(socket.closeReason, CloseCodes.reasonRevoked);
    });
  });
}

/// Run [action] and return the typed error it threw.
Future<TwinDropError> _catchError(Future<Object?> Function() action) async {
  try {
    await action();
  } on TwinDropError catch (e) {
    return e;
  }
  fail('expected a TwinDropError');
}
