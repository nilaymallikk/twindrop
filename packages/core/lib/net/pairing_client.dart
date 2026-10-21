import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/enums.dart';
import '../models/errors.dart';
import '../protocol/pairing_guard.dart';
import '../protocol/pairing_payload.dart';
import '../tls/tls_identity.dart';
import '../util/hashing.dart';
import '../util/logger.dart';

/// Manual pairing probe: the certificate fingerprint the user compares with
/// the desktop before any pin is stored (`PAIR-008`).
class ManualProbe {
  const ManualProbe({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.shortFingerprint,
  });

  final String host;
  final int port;
  final String fingerprint;

  /// Six uppercase hex characters shown on the phone.
  final String shortFingerprint;
}

/// Everything the phone needs after a successful pairing exchange.
class PairedDesktop {
  const PairedDesktop({
    required this.host,
    required this.port,
    required this.fingerprint,
    required this.hostDeviceId,
    required this.hostName,
    required this.deviceId,
    required this.deviceToken,
    required this.protocolVersion,
  });

  final String host;
  final int port;
  final String fingerprint;
  final String hostDeviceId;
  final String hostName;

  /// The phone's own persistent device id.
  final String deviceId;
  final String deviceToken;
  final int protocolVersion;
}

/// Phone-side pairing client (`docs/05` §Pairing, `PAIR-001`..`PAIR-005`).
class PairingClient {
  PairingClient({Logger? logger, Duration? pollTimeout})
      : _logger = logger,
        _pollTimeout = pollTimeout ?? const Duration(seconds: 90);

  final Logger? _logger;
  final Duration _pollTimeout;

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  /// Pair using a scanned QR payload. [onCode] receives the 4-digit
  /// confirmation code as soon as it is derived so the UI can show it; the
  /// future completes when the desktop approves.
  Future<PairedDesktop> pairWithPayload({
    required PairingPayload payload,
    required String clientDeviceId,
    required String displayName,
    required String platform,
    required void Function(String code) onCode,
    void Function(String desktopName)? onWait,
    DateTime Function()? now,
  }) async {
    final clock = now ?? DateTime.now;
    if (payload.isExpiredAt(clock())) {
      throw const PairingFailedError(expired: true);
    }
    final pin = payload.fingerprint;
    HttpClient? client;
    String? chosenHost;
    try {
      for (final host in payload.hosts) {
        try {
          client = TlsIdentity.pinnedHttpClient(pin);
          await _health(client, host, payload.port);
          chosenHost = host;
          break;
        } on Object {
          client?.close(force: true);
          client = null;
        }
      }
      if (client == null) {
        throw const NetworkError(
            'cannot reach the desktop; check that both devices are on the same '
            'Wi-Fi');
      }
      onWait?.call(payload.deviceName);
      final code = await _requestAndPoll(
        client: client,
        host: chosenHost!,
        port: payload.port,
        pin: pin,
        pairingToken: payload.pairingToken,
        hostDeviceId: payload.deviceId,
        hostName: payload.deviceName,
        clientDeviceId: clientDeviceId,
        displayName: displayName,
        platform: platform,
        onCode: onCode,
      );
      return code;
    } finally {
      client?.close(force: true);
    }
  }

  /// Ask the desktop for its certificate without trusting it. The callback
  /// captures the DER bytes and returns false, so the handshake is rejected and
  /// no pin is stored before the user confirms the short fingerprint.
  Future<ManualProbe> probeManual(String host, int port) async {
    List<int>? der;
    try {
      await SecureSocket.connect(
        host,
        port,
        context: SecurityContext(withTrustedRoots: false),
        onBadCertificate: (cert) {
          der = cert.der;
          return false;
        },
        timeout: const Duration(seconds: 5),
      ).then((socket) => socket.destroy());
    } on Object {
      // Rejection is expected; the certificate bytes are what we need.
    }
    final bytes = der;
    if (bytes == null) {
      throw const NetworkError('cannot read the desktop certificate');
    }
    final fp = sha256Hex(bytes);
    return ManualProbe(
      host: host,
      port: port,
      fingerprint: fp,
      shortFingerprint: shortFingerprint(fp),
    );
  }

  /// Continue manual pairing after the user confirmed the fingerprint and
  /// typed the code shown on the desktop.
  Future<PairedDesktop> pairManually({
    required ManualProbe probe,
    required String code,
    required String clientDeviceId,
    required String displayName,
    required String platform,
    required void Function(String code) onCode,
  }) async {
    final bytes = ManualPairingCode.decode(code);
    if (bytes == null) {
      throw const ValidationError('that pairing code is not valid');
    }
    final token = base64UrlToken(bytes);
    final client = TlsIdentity.pinnedHttpClient(probe.fingerprint);
    try {
      await _health(client, probe.host, probe.port);
      return await _requestAndPoll(
        client: client,
        host: probe.host,
        port: probe.port,
        pin: probe.fingerprint,
        pairingToken: token,
        hostDeviceId: '',
        hostName: '',
        clientDeviceId: clientDeviceId,
        displayName: displayName,
        platform: platform,
        onCode: onCode,
        shortFingerprintOverride: probe.shortFingerprint,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<PairedDesktop> _requestAndPoll({
    required HttpClient client,
    required String host,
    required int port,
    required String pin,
    required String pairingToken,
    required String hostDeviceId,
    required String hostName,
    required String clientDeviceId,
    required String displayName,
    required String platform,
    required void Function(String code) onCode,
    String? shortFingerprintOverride,
  }) async {
    final bytes = _decodeToken(pairingToken);
    final response = await _postJson(
      client,
      host,
      port,
      '/v1/pair/request',
      <String, dynamic>{
        'pairingToken': pairingToken,
        'clientInstanceId': clientDeviceId,
        'displayName': displayName,
        'platform': platform,
        'protocolVersion': 1,
      },
    );
    final request = PairRequestResponse.fromJson(response);
    final code = confirmationCode(
      pairingTokenBytes: bytes,
      requestId: request.requestId,
      fingerprintHex: pin,
    );
    onCode(code);

    final deadline = DateTime.now().add(_pollTimeout);
    while (!_cancelled && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(
        Duration(milliseconds: request.pollAfterMs.clamp(300, 5000)),
      );
      if (_cancelled) break;
      final statusJson = await _getStatus(
        client,
        host,
        port,
        request.requestId,
        request.pollSecret,
      );
      final status = PairStatusResponse.fromJson(statusJson);
      switch (status.state) {
        case PairingState.pendingApproval:
          continue;
        case PairingState.rejected:
          throw const PairingFailedError();
        case PairingState.expired:
          throw const PairingFailedError(expired: true);
        case PairingState.approved:
          final token = status.deviceToken;
          if (token == null || status.alreadyCollected) {
            throw const PairingFailedError();
          }
          return PairedDesktop(
            host: host,
            port: port,
            fingerprint: pin,
            hostDeviceId: status.hostDeviceId ?? hostDeviceId,
            hostName: status.hostName ?? hostName,
            deviceId: status.deviceId ?? clientDeviceId,
            deviceToken: token,
            protocolVersion: status.protocolVersion ?? 1,
          );
      }
    }
    throw const PairingFailedError(expired: true);
  }

  List<int> _decodeToken(String token) {
    try {
      final bytes = base64Url.decode(
          base64Url.normalize(token.padRight((token.length + 3) & ~3, '=')));
      if (bytes.length != 20 && bytes.length != 32) {
        throw const PairingFailedError();
      }
      return bytes;
    } on FormatException {
      throw const PairingFailedError();
    }
  }

  Future<void> _health(HttpClient client, String host, int port) async {
    final uri = Uri(scheme: 'https', host: host, port: port, path: '/v1/health');
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 5));
    final response = await request.close().timeout(const Duration(seconds: 5));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw NetworkError('desktop health check failed');
    }
    final json = jsonDecode(body);
    if (json is! Map || json['protocolVersion'] != 1) {
      throw const UnsupportedVersionError(
          'this desktop uses a different protocol; update TwinDrop');
    }
  }

  Future<Map<String, dynamic>> _postJson(
    HttpClient client,
    String host,
    int port,
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri(scheme: 'https', host: host, port: port, path: path);
    final request = await client.postUrl(uri).timeout(const Duration(seconds: 5));
    request.headers.contentType =
        ContentType('application', 'json', charset: 'utf-8');
    request.write(jsonEncode(body));
    final response = await request.close().timeout(const Duration(seconds: 8));
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 202 && response.statusCode != 200) {
      throw _apiError(text, response.statusCode);
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const ProtocolError('malformed pairing response');
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> _getStatus(
    HttpClient client,
    String host,
    int port,
    String requestId,
    String pollSecret,
  ) async {
    final uri = Uri(
      scheme: 'https',
      host: host,
      port: port,
      path: '/v1/pair/status',
      queryParameters: <String, String>{'requestId': requestId},
    );
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 5));
    request.headers.set('X-Poll-Secret', pollSecret);
    final response = await request.close().timeout(const Duration(seconds: 8));
    final text = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200) {
      throw _apiError(text, response.statusCode);
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const ProtocolError('malformed pairing status');
    return Map<String, dynamic>.from(decoded);
  }

  TwinDropError _apiError(String body, int status) {
    try {
      final json = jsonDecode(body);
      if (json is Map) {
        final error = ApiError.fromJson(Map<String, dynamic>.from(json));
        if (error.code == ErrorCodes.rateLimited) {
          return const RateLimitedError();
        }
        if (error.code == ErrorCodes.pairingExpired) {
          return const PairingFailedError(expired: true);
        }
        if (error.code == ErrorCodes.unsupportedVersion) {
          return const UnsupportedVersionError('update TwinDrop on both devices');
        }
        return PairingFailedError();
      }
    } on Object {
      // fall through
    }
    if (status == 403) return const ForbiddenError();
    if (status == 429) return const RateLimitedError();
    return const PairingFailedError();
  }
}
