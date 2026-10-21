import 'dart:convert';
import 'dart:io';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

import '../util/logger.dart';

/// The desktop host's self-signed TLS identity (`docs/05` §Transport).
///
/// * ECDSA P-256, valid 10 years, SANs list the current LAN IPs (informational;
///   trust comes from the pin).
/// * Key file is written with mode 0600.
/// * The pin is `SHA-256(DER certificate)` lowercase hex and is stable across
///   restarts because the PEM files are reused.
class TlsIdentity {
  const TlsIdentity({
    required this.certificatePem,
    required this.privateKeyPem,
    required this.fingerprint,
  });

  final String certificatePem;
  final String privateKeyPem;

  /// Lowercase hex SHA-256 of the DER certificate.
  final String fingerprint;

  /// First eight hex characters, used only as the mDNS hint.
  String get hint => fingerprint.substring(0, 8);

  /// Strict uppercase 6-character fingerprint for manual pairing comparison.
  String get shortFingerprint => fingerprint.substring(0, 6).toUpperCase();

  /// Server-side `SecurityContext` with no public roots.
  SecurityContext serverContext() {
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(certificatePem))
      ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
    return context;
  }

  /// Load or create the identity in [dir]. Existing files are reused so the pin
  /// never changes unexpectedly.
  static Future<TlsIdentity> loadOrCreate(
    Directory dir, {
    required List<String> sanIps,
    Logger? logger,
  }) async {
    final certFile = File('${dir.path}/cert.pem');
    final keyFile = File('${dir.path}/key.pem');
    await dir.create(recursive: true);
    if (await certFile.exists() && await keyFile.exists()) {
      final cert = await certFile.readAsString();
      final key = await keyFile.readAsString();
      try {
        final der = CryptoUtils.getBytesFromPEMString(cert);
        final fp = sha256.convert(der).toString();
        logger?.info('tls: loaded identity', fields: {'fp8': fp.substring(0, 8)});
        return TlsIdentity(
          certificatePem: cert,
          privateKeyPem: key,
          fingerprint: fp,
        );
      } on Object catch (e) {
        // A corrupt identity is not silently replaced: move it aside first and
        // generate a new one, which forces re-pairing explicitly.
        logger?.warn('tls: identity unreadable, regenerating',
            fields: {'error': e.runtimeType});
        final backup = DateTime.now().millisecondsSinceEpoch;
        await certFile.rename('${certFile.path}.corrupt-$backup');
        if (await keyFile.exists()) {
          await keyFile.rename('${keyFile.path}.corrupt-$backup');
        }
      }
    }

    final pair = CryptoUtils.generateEcKeyPair(curve: 'prime256v1');
    final priv = pair.privateKey as ECPrivateKey;
    final pub = pair.publicKey as ECPublicKey;
    final sans = <String>{
      '127.0.0.1',
      '::1',
      'localhost',
      ...sanIps.where((ip) => ip.isNotEmpty),
    }.toList(growable: false);
    final csr = X509Utils.generateEccCsrPem(
      {'commonName': 'TwinDrop', 'organizationName': 'TwinDrop'},
      priv,
      pub,
      san: sans,
    );
    final cert = X509Utils.generateSelfSignedCertificate(
      priv,
      csr,
      3650,
      sans: sans,
      notBefore: DateTime.now().subtract(const Duration(days: 1)),
    );
    final key = CryptoUtils.encodePrivateEcdsaKeyToPkcs8(priv);
    final der = CryptoUtils.getBytesFromPEMString(cert);
    final fp = sha256.convert(der).toString();

    await certFile.writeAsString(cert, flush: true);
    await keyFile.writeAsString(key, flush: true);
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', keyFile.path]);
      } on Object {
        // Best effort; the directory itself is user-private under XDG.
      }
    }
    logger?.info('tls: generated identity', fields: {'fp8': fp.substring(0, 8)});
    return TlsIdentity(
      certificatePem: cert,
      privateKeyPem: key,
      fingerprint: fp,
    );
  }

  /// Build a client `HttpClient` that trusts only a certificate whose DER
  /// SHA-256 equals [pin]. This is the *only* certificate callback TwinDrop
  /// ever installs; returning true unconditionally is forbidden (`docs/08`).
  static HttpClient pinnedHttpClient(String pin, {Duration? timeout}) {
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.badCertificateCallback = (cert, host, port) {
      return sha256.convert(cert.der).toString() == pin;
    };
    client.connectionTimeout = timeout ?? const Duration(seconds: 5);
    client.idleTimeout = const Duration(seconds: 30);
    return client;
  }

  /// Verify a DER certificate against a pin (used by tests and diagnostics).
  static bool matchesPin(List<int> der, String pin) =>
      sha256.convert(der).toString() == pin;

  /// Human diagnostic: is the file readable and is the private key valid?
  static Future<bool> privateKeyReadable(String keyPem) async {
    try {
      CryptoUtils.ecPrivateKeyFromPem(keyPem);
      return true;
    } on Object {
      return false;
    }
  }
}
