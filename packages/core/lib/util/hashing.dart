import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'ids.dart';

/// Namespace for deterministic conflict-copy ids. Fixed forever: changing it
/// would fork conflict copies between versions.
const String conflictCopyNamespace = '0f8fad5b-d9cb-469f-a165-70867728950e';

/// SHA-256 of [bytes] as lowercase hex.
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

/// Canonical content hash for the content group (`text`, `title`, `url`).
///
/// The three fields are joined with U+0000, which cannot appear unescaped in
/// JSON strings, so the encoding is unambiguous across devices.
String contentHashOf({required String text, String? title, String? url}) =>
    sha256Hex(utf8.encode('${text}\u0000${title ?? ''}\u0000${url ?? ''}'));

/// Hex SHA-256 used for device tokens stored on the desktop (PAIR-004).
String tokenHashOf(String token) => sha256Hex(utf8.encode(token));

/// Deterministic conflict copy id: `uuidv5(NS_CONFLICT, itemId + ":" + loserHash)`.
String conflictCopyIdFor(String itemId, String loserContentHash) =>
    deterministicId(conflictCopyNamespace, '$itemId:$loserContentHash');

/// 6-character short certificate fingerprint shown during manual pairing.
/// Uppercase hex of the first 3 bytes of the SHA-256 pin, e.g. `A1B2C3`.
String shortFingerprint(String pinHex) {
  final clean = pinHex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
  if (clean.length < 6) {
    throw FormatException('fingerprint too short: $pinHex');
  }
  return clean.substring(0, 6).toUpperCase();
}

/// 4-digit confirmation code shown on both screens during pairing.
///
/// `code = (HMAC-SHA256(pairingToken, requestId || fp) first 4 bytes as uint32)
/// mod 10000`, zero padded. Both implementations live here so desktop and phone
/// always compute the same value.
String confirmationCode({
  required List<int> pairingTokenBytes,
  required String requestId,
  required String fingerprintHex,
}) {
  final hmac = Hmac(sha256, pairingTokenBytes);
  final digest = hmac.convert(utf8.encode('$requestId$fingerprintHex')).bytes;
  final value =
      ((digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3]) &
      0xFFFFFFFF;
  return (value % 10000).toString().padLeft(4, '0');
}

/// Stable 8-hex mDNS fingerprint hint (never authority, `docs/05`).
String fingerprintHint(String pinHex) => pinHex.toLowerCase().substring(0, 8);
