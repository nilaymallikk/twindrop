// Throwaway spike: prove pure-Dart EC self-signed cert + pinned TLS works with
// dart:io server/client. Run: dart run tool/spike_tls.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

String fpOf(List<int> der) => sha256.convert(der).toString();

Future<void> main() async {
  final pair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
  final priv = pair.privateKey as ECPrivateKey;
  final pub = pair.publicKey as ECPublicKey;
  final csr = X509Utils.generateEccCsrPem(
    {'commonName': 'TwinDrop', 'organizationName': 'TwinDrop'},
    priv,
    pub,
    san: ['127.0.0.1'],
  );
  final certPem = X509Utils.generateSelfSignedCertificate(
    priv,
    csr,
    3650,
    sans: ['127.0.0.1'],
    notBefore: DateTime.now().subtract(const Duration(days: 1)),
  );
  final keyPem = CryptoUtils.encodePrivateEcdsaKeyToPkcs8(priv);
  final der = CryptoUtils.getBytesFromPEMString(certPem);
  final fp = fpOf(der);
  print('fp=$fp certBytes=${certPem.length} keyBytes=${keyPem.length}');

  final ctx = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certPem))
    ..usePrivateKeyBytes(utf8.encode(keyPem));

  final server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    ctx,
  );
  final port = server.port;
  print('bound $port');
  unawaited(
    server.forEach((req) async {
      if (req.uri.path == '/v1/ws' &&
          WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        ws.add('hello');
        await ws.close();
        return;
      }
      req.response
        ..statusCode = 200
        ..write('ok')
        ..close();
    }),
  );

  Future<HttpClient> client(String pin) async {
    final c = HttpClient(context: SecurityContext(withTrustedRoots: false));
    c.badCertificateCallback = (cert, host, p) => fpOf(cert.der) == pin;
    return c;
  }

  // REST correct pin
  final good = await client(fp);
  final req = await good.getUrl(Uri.parse('https://127.0.0.1:$port/v1/health'));
  final res = await req.close();
  print(
    'rest-good=${await res.transform(utf8.decoder).join()} ${res.statusCode}',
  );

  // REST wrong pin
  final bad = await client('00' * 32);
  try {
    final r2 = await (await bad.getUrl(
      Uri.parse('https://127.0.0.1:$port/v1/health'),
    )).close();
    print('rest-bad=UNEXPECTED ${r2.statusCode}');
  } catch (e) {
    print(
      'rest-bad=rejected ${e.runtimeType}: ${e.toString().split('\n').first}',
    );
  }

  // WS correct pin
  try {
    final ws = await WebSocket.connect(
      'wss://127.0.0.1:$port/v1/ws',
      customClient: await client(fp),
    );
    await for (final m in ws) {
      print('ws-good=$m');
    }
  } catch (e) {
    print('ws-good=FAILED $e');
  }

  // stability: reload key/cert from PEM, same fp
  final priv2 = CryptoUtils.ecPrivateKeyFromPem(keyPem);
  print('reloaded key d=${priv2.d == priv.d}');
  await server.close(force: true);
}
