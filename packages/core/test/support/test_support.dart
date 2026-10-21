/// Shared helpers for the TwinDrop core unit tests.
///
/// Everything here is deterministic: no wall-clock reads, no network, no
/// randomness. Callers inject the clock (`HlcClock(nowMs: ...)`), the logger
/// (`Logger(sink: ...)`) and the database (`AppDatabase.memory()`).
library;

import 'dart:io';

import 'package:twindrop_core/core.dart';

/// Deterministic HLC string (`<wallMs 15>-<counter 5>-<deviceId>`).
String hlcValue(int wallMs, int counter, String deviceId) =>
    Hlc(wallMs, counter, deviceId).value;

/// A lowercase UUID that satisfies `isUuid` (the remote-validation rule).
///
/// The remote validator only checks the *shape* (8-4-4-4-12 lowercase hex),
/// so a UUIDv7-looking prefix is enough and stays deterministic.
String testUuid(int n) =>
    '018f0000-0000-7000-8000-${n.toString().padLeft(12, '0')}';

/// Build an [Item] with a canonical content hash (content group).
///
/// [contentHash] is derived from `text`/`title`/`url` exactly like
/// `ItemBuilder` does, so the merge engine sees a consistent hash chain.
Item makeItem({
  required String id,
  ItemType type = ItemType.note,
  String text = 'hello',
  String? title,
  String? url,
  String? categoryId,
  String? sourceApp,
  String? sourceItemId,
  required String contentHlc,
  String? metaHlc,
  String? prevHash,
  bool pinned = false,
  bool deleted = false,
  String? deletedHlc,
  bool restored = false,
  bool isConflictCopy = false,
  int createdAt = 1000,
  String originDevice = 'device-a',
  String originName = 'Device A',
}) {
  final hash = contentHashOf(text: text, title: title, url: url);
  return Item(
    id: id,
    type: type,
    kind: url != null ? ItemKind.link : ItemKind.text,
    text: text,
    title: title,
    url: url,
    sourceApp: sourceApp,
    categoryId: type == ItemType.message ? null : categoryId,
    originDevice: originDevice,
    originName: originName,
    sourceItemId: sourceItemId,
    createdAt: createdAt,
    contentHash: hash,
    prevHash: prevHash,
    contentHlc: contentHlc,
    pinned: pinned,
    deleted: deleted,
    deletedHlc: deletedHlc,
    metaHlc: metaHlc ?? contentHlc,
    restored: restored,
    isConflictCopy: isConflictCopy,
  );
}

/// Build a [Category] row with a normalized name.
Category makeCategory({
  required String id,
  required String name,
  int sortOrder = 1,
  bool isInbox = false,
  bool deleted = false,
  required String metaHlc,
  String? color,
}) {
  return Category(
    id: id,
    name: name,
    normalizedName: normalizeCategoryName(name),
    color: color,
    sortOrder: sortOrder,
    isInbox: isInbox,
    metaHlc: metaHlc,
    deleted: deleted,
  );
}

/// A [Peer] row for the desktop side (stores only the token hash).
Peer makePeer({
  required String id,
  String name = 'Phone',
  String? tokenHash,
  String? certFp,
  int remoteSeq = 0,
  int ackedSeq = 0,
  int createdAt = 1000,
  int? revokedAt,
}) {
  return Peer(
    id: id,
    name: name,
    kind: PeerKind.phone,
    roleOfPeer: PeerRole.guest,
    tokenHash: tokenHash,
    certFp: certFp,
    remoteSeq: remoteSeq,
    ackedSeq: ackedSeq,
    revokedAt: revokedAt,
    createdAt: createdAt,
  );
}

/// Locate the package root (the directory holding `pubspec.yaml`) by walking
/// up from the current directory. Used by the source-grep tests.
String packageRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    if (File('${dir.path}/pubspec.yaml').existsSync()) return dir.path;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('package root not found from ${Directory.current.path}');
}
