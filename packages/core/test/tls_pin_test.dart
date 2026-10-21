import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';

import 'support/test_support.dart';

/// Start a loopback HTTPS server with the given identity.
Future<HttpServer> startLoopbackServer(TlsIdentity identity) async {
  final server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    identity.serverContext(),
  );
  server.listen((request) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.write('ok');
    await request.response.close();
  });
  return server;
}

/// Perform a full request/response cycle so that a TLS handshake failure is
/// always observed, no matter whether it surfaces on connect or on close.
Future<void> fetch(HttpClient client, Uri uri) async {
  final request = await client.getUrl(uri).timeout(const Duration(seconds: 10));
  final response = await request.close().timeout(const Duration(seconds: 10));
  await response.drain<void>();
}

void main() {
  late Directory tlsDir;

  setUp(() async {
    tlsDir = await Directory.systemTemp.createTemp('twindrop_tls_test_');
  });

  tearDown(() async {
    if (tlsDir.existsSync()) await tlsDir.delete(recursive: true);
  });

  group('TlsIdentity', () {
    test('creates a self-signed identity with a sha256 pin', () async {
      final identity = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      expect(identity.fingerprint.length, 64);
      expect(identity.fingerprint, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(identity.hint, identity.fingerprint.substring(0, 8));
      expect(identity.shortFingerprint,
          identity.fingerprint.substring(0, 6).toUpperCase());
      expect(File('${tlsDir.path}/cert.pem').existsSync(), isTrue);
      expect(File('${tlsDir.path}/key.pem').existsSync(), isTrue);
    });

    test('the fingerprint is stable across restarts', () async {
      final first = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      final second = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      expect(second.fingerprint, first.fingerprint,
          reason: 'the pin must never change silently');
      expect(second.certificatePem, first.certificatePem);
    });

    test('two different identities have different pins', () async {
      final other = await Directory.systemTemp.createTemp('twindrop_tls_b_');
      addTearDown(() => other.delete(recursive: true));
      final a = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      final b = await TlsIdentity.loadOrCreate(
        other,
        sanIps: const ['127.0.0.1'],
      );
      expect(a.fingerprint, isNot(b.fingerprint));
    });

    test('the private key is readable and parseable', () async {
      final identity = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      expect(await TlsIdentity.privateKeyReadable(identity.privateKeyPem), isTrue);
      expect(await TlsIdentity.privateKeyReadable('not a key'), isFalse);
    });
  });

  group('pin verification (fail closed)', () {
    test('accepts the certificate that produced the pin', () async {
      final identity = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      final der = CryptoUtils.getBytesFromPEMString(identity.certificatePem);
      expect(TlsIdentity.matchesPin(der, identity.fingerprint), isTrue);
    });

    test('rejects a certificate whose sha256 does not match', () async {
      final identity = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      final der = CryptoUtils.getBytesFromPEMString(identity.certificatePem);
      expect(TlsIdentity.matchesPin(der, '0' * 64), isFalse);
      expect(
        TlsIdentity.matchesPin(der, identity.fingerprint.replaceAll('a', 'b')),
        isFalse,
      );
    });

    test('rejects a tampered certificate', () async {
      final identity = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      final der = CryptoUtils.getBytesFromPEMString(identity.certificatePem);
      final tampered = List<int>.from(der)..[0] = (der[0] + 1) % 256;
      expect(TlsIdentity.matchesPin(tampered, identity.fingerprint), isFalse,
          reason: 'a single changed byte must invalidate the pin');
    });

    test('rejects an empty or truncated certificate', () async {
      final identity = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      final der = CryptoUtils.getBytesFromPEMString(identity.certificatePem);
      expect(TlsIdentity.matchesPin(const <int>[], identity.fingerprint), isFalse);
      expect(
        TlsIdentity.matchesPin(der.sublist(0, der.length - 1),
            identity.fingerprint),
        isFalse,
      );
    });
  });

  group('pinned client over loopback TLS', () {
    test('accepts the server when the pin matches', () async {
      final identity = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      final server = await startLoopbackServer(identity);
      addTearDown(() => server.close(force: true));

      final client = TlsIdentity.pinnedHttpClient(
        identity.fingerprint,
        timeout: const Duration(seconds: 5),
      );
      addTearDown(() => client.close(force: true));

      final request = await client
          .getUrl(Uri.parse('https://127.0.0.1:${server.port}/v1/health'))
          .timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(const Duration(seconds: 10));
      expect(response.statusCode, HttpStatus.ok);
      await response.drain<void>();
    });

    test('rejects the server when the pin does not match', () async {
      final identity = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      final server = await startLoopbackServer(identity);
      addTearDown(() => server.close(force: true));

      final client = TlsIdentity.pinnedHttpClient(
        'a' * 64,
        timeout: const Duration(seconds: 5),
      );
      addTearDown(() => client.close(force: true));

      await expectLater(
        fetch(
          client,
          Uri.parse('https://127.0.0.1:${server.port}/v1/health'),
        ),
        throwsA(isA<HandshakeException>()),
        reason: 'a wrong pin must fail the handshake, never be accepted',
      );
    });

    test('rejects a rotated certificate (re-pair required)', () async {
      final identity = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      // The desktop rotates its certificate: the phone still holds the old
      // pin, so the connection must fail instead of silently trusting the new
      // certificate.
      final rotatedDir =
          await Directory.systemTemp.createTemp('twindrop_tls_rotated_');
      addTearDown(() => rotatedDir.delete(recursive: true));
      final rotated = await TlsIdentity.loadOrCreate(
        rotatedDir,
        sanIps: const ['127.0.0.1'],
      );
      expect(rotated.fingerprint, isNot(identity.fingerprint));

      final server = await startLoopbackServer(rotated);
      addTearDown(() => server.close(force: true));

      final client = TlsIdentity.pinnedHttpClient(
        identity.fingerprint,
        timeout: const Duration(seconds: 5),
      );
      addTearDown(() => client.close(force: true));

      await expectLater(
        fetch(
          client,
          Uri.parse('https://127.0.0.1:${server.port}/v1/health'),
        ),
        throwsA(isA<HandshakeException>()),
      );
    });

    test('the pin of another identity does not unlock this server', () async {
      final identity = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: const ['127.0.0.1'],
      );
      final otherDir =
          await Directory.systemTemp.createTemp('twindrop_tls_other_');
      addTearDown(() => otherDir.delete(recursive: true));
      final other = await TlsIdentity.loadOrCreate(
        otherDir,
        sanIps: const ['127.0.0.1'],
      );

      final server = await startLoopbackServer(identity);
      addTearDown(() => server.close(force: true));

      final client = TlsIdentity.pinnedHttpClient(
        other.fingerprint,
        timeout: const Duration(seconds: 5),
      );
      addTearDown(() => client.close(force: true));

      await expectLater(
        fetch(
          client,
          Uri.parse('https://127.0.0.1:${server.port}/v1/health'),
        ),
        throwsA(isA<HandshakeException>()),
      );
    });
  });

  group('source guards (docs/08: no "badCertificateCallback => true")', () {
    test('every certificate callback compares against a pin', () {
      final libDir = Directory('${packageRoot()}/lib');
      final files = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty);

      var callbacks = 0;
      for (final file in files) {
        final source = file.readAsStringSync();
        var index = source.indexOf('badCertificateCallback');
        while (index != -1) {
          callbacks++;
          final end = (index + 400).clamp(0, source.length);
          final snippet = source.substring(index, end);
          expect(snippet.contains('=> true'), isFalse,
              reason: '${file.path}: the callback must never accept blindly');
          expect(snippet.contains('return true'), isFalse,
              reason: '${file.path}: the callback must never accept blindly');
          expect(snippet.contains('sha256'), isTrue,
              reason: '${file.path}: the callback must hash the certificate');
          expect(snippet.contains('pin'), isTrue,
              reason: '${file.path}: the callback must compare with the pin');
          index = source.indexOf('badCertificateCallback', index + 1);
        }
      }
      expect(callbacks, greaterThan(0),
          reason: 'the pinned client must still exist');
    });

    test('no public-CA trust is configured for the pinned client', () {
      final source = File(
        '${packageRoot()}/lib/tls/tls_identity.dart',
      ).readAsStringSync();
      expect(source.contains('withTrustedRoots: false'), isTrue);
    });
  });
}
