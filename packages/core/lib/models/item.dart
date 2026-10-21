import 'enums.dart';

/// A chat message or a notepad note. The same row type carries both so cursor
/// sync only has to replicate one entity table (`docs/04-data-model.md`).
///
/// Messages are immutable: their content group never changes after creation;
/// only the meta group (delete/pin) may change.
class Item {
  const Item({
    required this.id,
    required this.type,
    required this.kind,
    required this.text,
    this.title,
    this.url,
    this.sourceApp,
    this.categoryId,
    required this.originDevice,
    required this.originName,
    this.sourceItemId,
    required this.createdAt,
    required this.contentHash,
    this.prevHash,
    required this.contentHlc,
    this.pinned = false,
    this.deleted = false,
    this.deletedHlc,
    required this.metaHlc,
    this.restored = false,
    this.isConflictCopy = false,
  });

  /// UUIDv7, lowercase.
  final String id;
  final ItemType type;
  final ItemKind kind;
  final String text;
  final String? title;
  final String? url;
  final String? sourceApp;

  /// Notes only: category id (`inbox` is the fixed default).
  final String? categoryId;

  /// Device id of the device that first created this row.
  final String originDevice;

  /// Human device label captured at creation time (display only).
  final String originName;

  /// Set when a note was created from a chat message ("Save to Notepad").
  final String? sourceItemId;

  /// Wall-clock creation time, epoch milliseconds UTC. Display only.
  final int createdAt;

  // ---- content group (text/title/url) ----
  final String contentHash;
  final String? prevHash;
  final String contentHlc;

  // ---- meta group (category_id/pinned/deleted) ----
  final bool pinned;
  final bool deleted;
  final String? deletedHlc;
  final String metaHlc;

  // ---- conflict handling ----
  final bool restored;
  final bool isConflictCopy;

  bool get isMessage => type == ItemType.message;
  bool get isNote => type == ItemType.note;
  bool get isLink => kind == ItemKind.link && url != null;

  Item copyWith({
    String? id,
    ItemType? type,
    ItemKind? kind,
    String? text,
    String? title,
    String? url,
    String? sourceApp,
    String? categoryId,
    String? originDevice,
    String? originName,
    String? sourceItemId,
    int? createdAt,
    String? contentHash,
    String? prevHash,
    String? contentHlc,
    bool? pinned,
    bool? deleted,
    String? deletedHlc,
    String? metaHlc,
    bool? restored,
    bool? isConflictCopy,
    bool clearDeletedHlc = false,
    bool clearTitle = false,
    bool clearUrl = false,
    bool clearSourceItemId = false,
  }) {
    return Item(
      id: id ?? this.id,
      type: type ?? this.type,
      kind: kind ?? this.kind,
      text: text ?? this.text,
      title: clearTitle ? null : (title ?? this.title),
      url: clearUrl ? null : (url ?? this.url),
      sourceApp: sourceApp ?? this.sourceApp,
      categoryId: categoryId ?? this.categoryId,
      originDevice: originDevice ?? this.originDevice,
      originName: originName ?? this.originName,
      sourceItemId: clearSourceItemId ? null : (sourceItemId ?? this.sourceItemId),
      createdAt: createdAt ?? this.createdAt,
      contentHash: contentHash ?? this.contentHash,
      prevHash: prevHash ?? this.prevHash,
      contentHlc: contentHlc ?? this.contentHlc,
      pinned: pinned ?? this.pinned,
      deleted: deleted ?? this.deleted,
      deletedHlc: clearDeletedHlc ? null : (deletedHlc ?? this.deletedHlc),
      metaHlc: metaHlc ?? this.metaHlc,
      restored: restored ?? this.restored,
      isConflictCopy: isConflictCopy ?? this.isConflictCopy,
    );
  }

  /// Canonical JSON used by the WS change payload and the quarantine log.
  /// Field names are stable wire names.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': type.wire,
        'kind': kind.wire,
        'text': text,
        if (title != null) 'title': title,
        if (url != null) 'url': url,
        if (sourceApp != null) 'sourceApp': sourceApp,
        if (categoryId != null) 'categoryId': categoryId,
        'originDevice': originDevice,
        'originName': originName,
        if (sourceItemId != null) 'sourceItemId': sourceItemId,
        'createdAt': createdAt,
        'contentHash': contentHash,
        if (prevHash != null) 'prevHash': prevHash,
        'contentHlc': contentHlc,
        'pinned': pinned,
        'deleted': deleted,
        if (deletedHlc != null) 'deletedHlc': deletedHlc,
        'metaHlc': metaHlc,
        'restored': restored,
        'isConflictCopy': isConflictCopy,
      };

  static Item fromJson(Map<String, dynamic> j) {
    T? opt<T>(String k) => j[k] as T?;
    return Item(
      id: j['id'] as String,
      type: ItemType.parse(j['type'] as String),
      kind: ItemKind.parse(j['kind'] as String),
      text: j['text'] as String,
      title: opt<String>('title'),
      url: opt<String>('url'),
      sourceApp: opt<String>('sourceApp'),
      categoryId: opt<String>('categoryId'),
      originDevice: j['originDevice'] as String,
      originName: j['originName'] as String,
      sourceItemId: opt<String>('sourceItemId'),
      createdAt: (j['createdAt'] as num).toInt(),
      contentHash: j['contentHash'] as String,
      prevHash: opt<String>('prevHash'),
      contentHlc: j['contentHlc'] as String,
      pinned: (j['pinned'] as bool?) ?? false,
      deleted: (j['deleted'] as bool?) ?? false,
      deletedHlc: opt<String>('deletedHlc'),
      metaHlc: j['metaHlc'] as String,
      restored: (j['restored'] as bool?) ?? false,
      isConflictCopy: (j['isConflictCopy'] as bool?) ?? false,
    );
  }

  @override
  String toString() =>
      'Item($id, ${type.wire}/${kind.wire}, deleted=$deleted, conflict=$isConflictCopy)';
}
