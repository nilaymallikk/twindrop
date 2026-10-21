import 'dart:convert';

import '../models/category.dart';
import '../models/enums.dart';
import '../models/item.dart';
import '../validators/validators.dart';

final RegExp _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');

bool isUuid(String value) => _uuid.hasMatch(value);

/// Validation of rows received from a paired peer.
///
/// A valid-but-invalid payload (bad URL scheme, oversize text) goes to
/// quarantine, not a silent drop (`SYNC-006`). Structural problems that mean
/// we cannot understand the data at all (unknown entity/version) are handled
/// by the sync engine as "stop and show Update needed" (`SYNC-007`).
QuarantineReason? validateRemoteItem(Item item) {
  if (!isUuid(item.id)) return QuarantineReason.malformed;
  if (item.text.length > maxNoteBytes) return QuarantineReason.oversize;
  if (!isWellFormedUnicode(item.text)) return QuarantineReason.malformed;
  if (utf8.encode(item.text).length > maxNoteBytes) {
    return QuarantineReason.oversize;
  }
  if (item.type == ItemType.message) {
    if (item.text.trim().isEmpty) return QuarantineReason.validationFailed;
    if (utf8.encode(item.text).length > maxMessageBytes) {
      return QuarantineReason.oversize;
    }
  }
  if (!isValidTitle(item.title)) return QuarantineReason.oversize;
  if (!_sha256.hasMatch(item.contentHash)) return QuarantineReason.malformed;
  if (item.url != null && !isValidWebUrl(item.url)) {
    return QuarantineReason.invalidUrl;
  }
  for (final hlc in [item.contentHlc, item.metaHlc, item.deletedHlc]) {
    if (hlc == null) continue;
    if (HlcFormat.isInvalid(hlc)) return QuarantineReason.malformed;
  }
  if (item.deleted && item.deletedHlc == null) {
    return QuarantineReason.malformed;
  }
  return null;
}

/// Category validation. Returns null when usable; the merge engine normalises
/// cosmetic fields (name/normalizedName) itself.
QuarantineReason? validateRemoteCategory(Category c) {
  if (c.id != Category.inboxId && !isUuid(c.id)) {
    return QuarantineReason.malformed;
  }
  if (!isValidCategoryName(c.name)) return QuarantineReason.validationFailed;
  if (HlcFormat.isInvalid(c.metaHlc)) return QuarantineReason.malformed;
  if (c.sortOrder < -1000000 || c.sortOrder > 1000000) {
    return QuarantineReason.validationFailed;
  }
  return null;
}

/// Small helper so call sites don't import HLC internals just to validate.
abstract final class HlcFormat {
  static final RegExp _re = RegExp(r'^\d{15}-\d{5}-.+$');

  static bool isInvalid(String value) {
    if (!_re.hasMatch(value)) return true;
    final parts = value.split('-');
    if (parts.length < 3) return true;
    final wall = int.tryParse(parts[0]);
    final counter = int.tryParse(parts[1]);
    if (wall == null || counter == null) return true;
    if (counter < 0 || counter > 99999) return true;
    return false;
  }
}
