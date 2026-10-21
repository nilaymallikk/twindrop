import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../models/errors.dart';
import '../sync/remote_validation.dart' show isUuid;

/// One-time pairing payload carried in the QR code (`docs/05` §Pairing).
///
/// Contains no long-lived secret: only the ephemeral pairing token, the TLS
/// pin, addresses and expiry. Parsing is deliberately strict — every field is
/// type-checked, ranges are bounded and the base64url/JSON envelope is
/// validated — because this is untrusted input from a camera.
class PairingPayload {
  const PairingPayload({
    required this.hosts,
    required this.port,
    required this.fingerprint,
    required this.pairingToken,
    required this.expiresAt,
    required this.deviceName,
    required this.deviceId,
  });

  static const String appId = 'twindrop';
  static const int version = 1;
  static const int maxEncodedLength = 4096;
  static const int pairingTokenLength = 32;
  static const int maxHosts = 8;

  /// Candidate LAN addresses (IPv4/IPv6 literals), in priority order.
  final List<String> hosts;
  final int port;

  /// `SHA-256(DER certificate)` lowercase hex — the pin, never a hint.
  final String fingerprint;

  /// Base64url (unpadded) of 32 random bytes.
  final String pairingToken;

  /// Absolute expiry (UTC).
  final DateTime expiresAt;

  final String deviceName;

  /// Host device id (UUIDv7).
  final String deviceId;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);

  /// Raw pairing-token bytes (for the confirmation code HMAC).
  List<int> get pairingTokenBytes => base64Url.decode(base64Url.normalize(
        pairingToken.padRight((pairingToken.length + 3) & ~3, '='),
      ));

  String encode() => base64Url
      .encode(utf8.encode(jsonEncode(toJson())))
      .replaceAll('=', '');

  Map<String, dynamic> toJson() => <String, dynamic>{
        'app': appId,
        'v': version,
        'hosts': hosts,
        'port': port,
        'fp': fingerprint,
        'pt': pairingToken,
        'exp': expiresAt.toUtc().toIso8601String(),
        'name': deviceName,
        'id': deviceId,
      };

  /// Strict parse of the QR string. Throws [ProtocolError] for malformed data
  /// and [UnsupportedVersionError] for a newer protocol version.
  static PairingPayload parse(String raw) {
    if (raw.length > maxEncodedLength) {
      throw const PayloadTooLargeError('pairing payload too large');
    }
    final trimmed = raw.trim();
    if (trimmed.isEmpty) throw const ProtocolError('empty pairing payload');
    if (trimmed.contains(RegExp(r'\s'))) {
      throw const ProtocolError('pairing payload contains whitespace');
    }
    List<int> bytes;
    try {
      bytes = base64Url.decode(base64Url.normalize(
        trimmed.padRight((trimmed.length + 3) & ~3, '='),
      ));
    } on FormatException {
      throw const ProtocolError('pairing payload is not base64url');
    }
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException('not an object');
      json = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const ProtocolError('pairing payload is not a JSON object');
    } on Object {
      throw const ProtocolError('pairing payload is not JSON');
    }

    if (json['app'] != appId) {
      throw const ProtocolError('not a TwinDrop pairing code');
    }
    final v = json['v'];
    if (v is! int) throw const ProtocolError('missing protocol version');
    if (v > version) {
      throw const UnsupportedVersionError(
          'this QR code comes from a newer TwinDrop version');
    }
    if (v != version) throw const ProtocolError('unsupported QR version');

    final hostsRaw = json['hosts'];
    if (hostsRaw is! List || hostsRaw.isEmpty || hostsRaw.length > maxHosts) {
      throw const ProtocolError('invalid host list');
    }
    final hosts = <String>[];
    for (final h in hostsRaw) {
      if (h is! String || h.isEmpty || h.length > 45) {
        throw const ProtocolError('invalid host');
      }
      if (InternetAddress.tryParse(h) == null) {
        throw const ProtocolError('invalid host address');
      }
      hosts.add(h);
    }

    final port = json['port'];
    if (port is! int || port < 1 || port > 65535) {
      throw const ProtocolError('invalid port');
    }

    final fp = json['fp'];
    if (fp is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(fp)) {
      throw const ProtocolError('invalid fingerprint');
    }

    final pt = json['pt'];
    if (pt is! String || pt.length < 40 || pt.length > 60) {
      throw const ProtocolError('invalid pairing token');
    }
    List<int> tokenBytes;
    try {
      tokenBytes = base64Url.decode(base64Url.normalize(
        pt.padRight((pt.length + 3) & ~3, '='),
      ));
    } on FormatException {
      throw const ProtocolError('invalid pairing token encoding');
    }
    if (tokenBytes.length != pairingTokenLength) {
      throw const ProtocolError('invalid pairing token length');
    }
    if (base64Url.encode(tokenBytes).replaceAll('=', '') != pt) {
      throw const ProtocolError('non-canonical pairing token');
    }

    final expRaw = json['exp'];
    if (expRaw is! String || expRaw.isEmpty) {
      throw const ProtocolError('missing expiry');
    }
    final exp = DateTime.tryParse(expRaw);
    if (exp == null) throw const ProtocolError('invalid expiry');
    final expUtc = exp.toUtc();

    final name = json['name'];
    if (name is! String || name.trim().isEmpty || name.length > 100) {
      throw const ProtocolError('invalid device name');
    }
    final id = json['id'];
    if (id is! String || !isUuid(id)) {
      throw const ProtocolError('invalid device id');
    }

    return PairingPayload(
      hosts: hosts,
      port: port,
      fingerprint: fp,
      pairingToken: pt,
      expiresAt: expUtc,
      deviceName: name.trim(),
      deviceId: id,
    );
  }
}

/// Human-readable manual pairing code (`PAIR-008`): 8 groups of 4 base32
/// characters (160 bits of the pairing token). Typed when the camera is not
/// available; the desktop verifies the prefix of the session token.
abstract final class ManualPairingCode {
  static const String alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  static const int groups = 8;
  static const int groupLength = 4;
  static const int codeLength = groups * groupLength;

  /// Encode the first 20 bytes of the pairing token as 32 base32 chars.
  static String encode(List<int> tokenBytes) {
    if (tokenBytes.length < 20) {
      throw ArgumentError('pairing token too short');
    }
    final input = tokenBytes.sublist(0, 20);
    final buffer = StringBuffer();
    var bits = 0;
    var value = 0;
    for (final byte in input) {
      value = (value << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        buffer.write(alphabet[(value >> bits) & 0x1f]);
      }
    }
    if (bits > 0) {
      buffer.write(alphabet[(value << (5 - bits)) & 0x1f]);
    }
    final chars = buffer.toString();
    final padded = chars.padRight(codeLength, alphabet[0]);
    return List.generate(groups, (g) => padded.substring(g * groupLength, (g + 1) * groupLength)).join(' ');
  }

  /// Parse a user-typed code (case-insensitive, spaces/dashes ignored) back to
  /// 20 bytes. Returns null when invalid.
  static List<int>? decode(String input) {
    final clean = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (clean.length != codeLength) return null;
    final bytes = <int>[];
    var bits = 0;
    var value = 0;
    for (final ch in clean.split('')) {
      final idx = alphabet.indexOf(ch);
      if (idx < 0) return null;
      value = (value << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        bytes.add((value >> bits) & 0xff);
      }
    }
    return bytes;
  }

  /// Constant-time comparison of the entered code bytes against the token.
  static bool matches(List<int> entered, List<int> tokenBytes) {
    if (entered.length > tokenBytes.length) return false;
    var diff = 0;
    for (var i = 0; i < entered.length; i++) {
      diff |= entered[i] ^ tokenBytes[i];
    }
    return diff == 0;
  }
}

/// Human-readable grouping helper used by the desktop UI ("ABCD-EFGH-…").
String groupManualCodeForDisplay(String code) =>
    code.replaceAll(' ', '-');

/// Cryptographically secure random bytes.
List<int> secureRandomBytes(int length) {
  final rnd = Random.secure();
  return List<int>.generate(length, (_) => rnd.nextInt(256));
}

/// Base64url unpadded encoding used for tokens.
String base64UrlToken(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');
