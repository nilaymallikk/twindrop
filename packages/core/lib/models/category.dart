/// A notepad category. `Inbox` is a fixed row with id `inbox` on both devices
/// (NOTE-002); its `deleted` flag is ignored by the merge engine.
class Category {
  const Category({
    required this.id,
    required this.name,
    required this.normalizedName,
    this.color,
    required this.sortOrder,
    required this.isInbox,
    required this.metaHlc,
    this.deleted = false,
  });

  /// Fixed id for the Inbox category.
  static const String inboxId = 'inbox';
  static const String inboxName = 'Inbox';

  final String id;
  final String name;

  /// Lower-cased, whitespace-collapsed name; uniqueness key for non-deleted
  /// categories (Note-001).
  final String normalizedName;
  final String? color;
  final int sortOrder;
  final bool isInbox;
  final String metaHlc;
  final bool deleted;

  Category copyWith({
    String? name,
    String? normalizedName,
    String? color,
    int? sortOrder,
    bool? deleted,
    String? metaHlc,
    bool clearColor = false,
  }) =>
      Category(
        id: id,
        name: name ?? this.name,
        normalizedName: normalizedName ?? this.normalizedName,
        color: clearColor ? null : (color ?? this.color),
        sortOrder: sortOrder ?? this.sortOrder,
        isInbox: isInbox,
        metaHlc: metaHlc ?? this.metaHlc,
        deleted: deleted ?? this.deleted,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'normalizedName': normalizedName,
        if (color != null) 'color': color,
        'sortOrder': sortOrder,
        'isInbox': isInbox,
        'metaHlc': metaHlc,
        'deleted': deleted,
      };

  static Category fromJson(Map<String, dynamic> j) => Category(
        id: j['id'] as String,
        name: j['name'] as String,
        normalizedName: j['normalizedName'] as String,
        color: j['color'] as String?,
        sortOrder: (j['sortOrder'] as num).toInt(),
        isInbox: (j['isInbox'] as bool?) ?? false,
        metaHlc: j['metaHlc'] as String,
        deleted: (j['deleted'] as bool?) ?? false,
      );

  @override
  String toString() => 'Category($id, $name, deleted=$deleted)';
}
