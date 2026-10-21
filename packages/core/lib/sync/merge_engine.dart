import '../db/database.dart';
import '../db/store_ops.dart';
import '../models/category.dart';
import '../models/enums.dart';
import '../models/item.dart';
import '../util/hashing.dart';
import '../util/hlc.dart';
import '../util/logger.dart';

/// Result of merging one remote row (`docs/04` §Merge rules).
class MergeResult {
  const MergeResult({
    required this.item,
    this.inserted = false,
    this.changed = false,
    this.restored = false,
    this.conflictCopyCreated = false,
    this.conflictCopy,
  });

  final Item? item;
  final bool inserted;
  final bool changed;
  final bool restored;
  final bool conflictCopyCreated;
  final Item? conflictCopy;

  static const MergeResult none = MergeResult(item: null);
}

class CategoryMergeResult {
  const CategoryMergeResult({
    required this.category,
    this.inserted = false,
    this.changed = false,
  });

  final Category? category;
  final bool inserted;
  final bool changed;
}

/// Deterministic merge of remote rows into the local replica.
///
/// Both peers run this exact code, so applying the same two rows in either
/// order yields the same final state (`SYNC-005`). The engine must be called
/// inside a transaction; callers append change-log rows via the returned
/// [MergeResult.changed] flags and are responsible for `ChangeBus.notify()`
/// after the commit.
class MergeEngine {
  MergeEngine({
    required AppDatabase db,
    required HlcClock clock,
    required Logger logger,
  }) : _db = db,
       _clock = clock,
       _logger = logger;

  final AppDatabase _db;
  final HlcClock _clock;
  final Logger _logger;

  // --------------------------------------------------------------- items ---

  Future<MergeResult> mergeItem(Item remote, {String? fromPeer}) async {
    final local = await _db.itemById(remote.id);
    if (local == null) {
      await _db.putItem(remote);
      await _db.ftsUpsert(remote);
      await _db.appendChange('item', remote.id, sourcePeer: fromPeer);
      _logger.debug(
        'merge: inserted item',
        fields: {'id': remote.id, 'from': fromPeer},
      );
      return MergeResult(item: remote, inserted: true, changed: true);
    }

    // ---- content group (`text`/`title`/`url`) ----
    Item contentSource;
    Item? contentLoser;
    if (remote.contentHash == local.contentHash) {
      contentSource = local;
    } else if (remote.prevHash == local.contentHash) {
      // Fast-forward: remote directly follows our content.
      contentSource = remote;
    } else if (local.prevHash == remote.contentHash) {
      // Remote is stale: keep ours.
      contentSource = local;
    } else {
      // Concurrent edit: higher content_hlc wins, loser becomes a conflict copy.
      final cmp = compareHlcValues(remote.contentHlc, local.contentHlc);
      final remoteWins =
          cmp > 0 ||
          (cmp == 0 && remote.contentHash.compareTo(local.contentHash) > 0);
      contentSource = remoteWins ? remote : local;
      contentLoser = remoteWins ? local : remote;
    }

    // ---- meta group: last-writer-wins by meta_hlc ----
    final metaCmp = compareHlcValues(remote.metaHlc, local.metaHlc);
    final MetaGroup meta;
    if (metaCmp > 0) {
      meta = MetaGroup.from(remote);
    } else if (metaCmp < 0) {
      meta = MetaGroup.from(local);
    } else {
      // Same HLC on both sides but different values can only come from a
      // derived rule (e.g. delete-vs-edit restore). Resolve deterministically.
      meta = MetaGroup.combine(local, remote);
    }

    final merged = Item(
      id: local.id,
      // Type/kind are creation facts and never mutate; take the content
      // winner's values so both peers derive the same row.
      type: contentSource.type,
      kind: contentSource.url != null ? ItemKind.link : ItemKind.text,
      text: contentSource.text,
      title: contentSource.title,
      url: contentSource.url,
      sourceApp: local.sourceApp,
      categoryId: contentSource.type == ItemType.message
          ? null
          : meta.categoryId,
      originDevice: local.originDevice,
      originName: local.originName,
      sourceItemId: local.sourceItemId,
      createdAt: local.createdAt,
      contentHash: contentSource.contentHash,
      prevHash: contentSource.prevHash,
      contentHlc: contentSource.contentHlc,
      pinned: meta.pinned,
      deleted: meta.deleted,
      deletedHlc: meta.deletedHlc,
      metaHlc: meta.metaHlc,
      restored: local.restored || remote.restored,
      isConflictCopy: local.isConflictCopy || remote.isConflictCopy,
    );

    // ---- delete vs edit: never lose content to a concurrent delete ----
    var finalItem = merged;
    var restored = false;
    if (merged.deleted && merged.deletedHlc != null) {
      if (compareHlcValues(merged.contentHlc, merged.deletedHlc!) > 0) {
        finalItem = merged.copyWith(deleted: false, restored: true);
        restored = true;
        _logger.debug(
          'merge: restored item after concurrent delete',
          fields: {'id': merged.id},
        );
      }
    }

    var changed = false;
    if (!_sameItem(finalItem, local)) {
      await _db.putItem(finalItem);
      await _db.ftsUpsert(finalItem);
      await _db.appendChange('item', finalItem.id, sourcePeer: fromPeer);
      changed = true;
    }

    // ---- conflict copy of the loser ----
    Item? copy;
    var copyCreated = false;
    if (contentLoser != null) {
      copy = _conflictCopyOf(
        loser: contentLoser,
        itemId: local.id,
        categoryId: finalItem.categoryId,
        metaHlc: finalItem.metaHlc,
      );
      final existing = await _db.itemById(copy.id);
      if (existing == null) {
        await _db.putItem(copy);
        await _db.ftsUpsert(copy);
        await _db.appendChange('item', copy.id, sourcePeer: fromPeer);
        copyCreated = true;
        _logger.info('merge: created conflict copy', fields: {'id': copy.id});
      } else {
        copy = existing;
      }
    }

    return MergeResult(
      item: finalItem,
      changed: changed,
      restored: restored,
      conflictCopyCreated: copyCreated,
      conflictCopy: copy,
    );
  }

  /// Builds the conflict copy of the losing content. The id is deterministic
  /// (`uuidv5(NS_CONFLICT, itemId + ":" + loserContentHash)`) and every other
  /// field is derived from the loser row, so both devices create the exact
  /// same copy (`docs/04` rule 2, `SYNC-005`).
  Item _conflictCopyOf({
    required Item loser,
    required String itemId,
    required String? categoryId,
    required String metaHlc,
  }) {
    final baseTitle = (loser.title != null && loser.title!.trim().isNotEmpty)
        ? loser.title!
        : loser.text;
    final trimmed = baseTitle.trim();
    final snippet = trimmed.length <= 40
        ? trimmed
        : trimmed.substring(0, 40).trim();
    var title = 'Conflict copy: $snippet';
    if (title.length > 200) title = title.substring(0, 200);
    return Item(
      id: conflictCopyIdFor(itemId, loser.contentHash),
      type: ItemType.note,
      kind: loser.url != null ? ItemKind.link : ItemKind.text,
      text: loser.text,
      title: title,
      url: loser.url,
      sourceApp: loser.sourceApp,
      categoryId: categoryId,
      originDevice: loser.originDevice,
      originName: loser.originName,
      sourceItemId: loser.sourceItemId,
      createdAt: loser.createdAt,
      contentHash: loser.contentHash,
      prevHash: loser.prevHash,
      contentHlc: loser.contentHlc,
      pinned: false,
      deleted: false,
      deletedHlc: null,
      metaHlc: metaHlc,
      restored: false,
      isConflictCopy: true,
    );
  }

  bool _sameItem(Item a, Item b) =>
      a.type == b.type &&
      a.kind == b.kind &&
      a.text == b.text &&
      a.title == b.title &&
      a.url == b.url &&
      a.categoryId == b.categoryId &&
      a.contentHash == b.contentHash &&
      a.prevHash == b.prevHash &&
      a.contentHlc == b.contentHlc &&
      a.pinned == b.pinned &&
      a.deleted == b.deleted &&
      a.deletedHlc == b.deletedHlc &&
      a.metaHlc == b.metaHlc &&
      a.restored == b.restored &&
      a.isConflictCopy == b.isConflictCopy;

  // ----------------------------------------------------------- categories ---

  Future<CategoryMergeResult> mergeCategory(
    Category remote, {
    String? fromPeer,
  }) async {
    final local = await _db.categoryById(remote.id);
    if (local == null) {
      final row = remote.id == Category.inboxId
          ? remote.copyWith(
              name: Category.inboxName,
              normalizedName: Category.inboxName.toLowerCase(),
              deleted: false,
            )
          : remote;
      await _db.putCategory(row);
      await _db.appendChange('category', row.id, sourcePeer: fromPeer);
      await _resolveNameCollisions(fromPeer: fromPeer);
      return CategoryMergeResult(category: row, inserted: true, changed: true);
    }

    final cmp = compareHlcValues(remote.metaHlc, local.metaHlc);
    var merged = local;
    if (cmp > 0) {
      merged = local.copyWith(
        name: remote.name,
        normalizedName: remote.normalizedName,
        color: remote.color,
        sortOrder: remote.sortOrder,
        deleted: remote.deleted,
        metaHlc: remote.metaHlc,
        clearColor: remote.color == null,
      );
    } else if (cmp == 0) {
      // Same HLC: deterministic combination (favour the surviving row).
      merged = Category(
        id: local.id,
        name: local.deleted && !remote.deleted ? remote.name : local.name,
        normalizedName: local.deleted && !remote.deleted
            ? remote.normalizedName
            : local.normalizedName,
        color: local.deleted && !remote.deleted ? remote.color : local.color,
        sortOrder: local.deleted && !remote.deleted
            ? remote.sortOrder
            : local.sortOrder,
        isInbox:
            local.id == Category.inboxId || local.isInbox || remote.isInbox,
        metaHlc: local.metaHlc,
        deleted: local.deleted && remote.deleted,
      );
    }
    if (merged.id == Category.inboxId) {
      merged = merged.copyWith(
        name: Category.inboxName,
        normalizedName: Category.inboxName.toLowerCase(),
        deleted: false,
      );
    }

    final changed = !_sameCategory(merged, local);
    if (changed) {
      await _db.putCategory(merged);
      await _db.appendChange('category', merged.id, sourcePeer: fromPeer);
    }
    await _resolveNameCollisions(fromPeer: fromPeer);
    return CategoryMergeResult(
      category: merged,
      inserted: false,
      changed: changed,
    );
  }

  bool _sameCategory(Category a, Category b) =>
      a.name == b.name &&
      a.normalizedName == b.normalizedName &&
      a.color == b.color &&
      a.sortOrder == b.sortOrder &&
      a.deleted == b.deleted &&
      a.metaHlc == b.metaHlc;

  /// `docs/04` rule 5: concurrently created categories sharing a normalized
  /// name are collapsed deterministically. Inbox always wins; otherwise the
  /// smaller id survives and the loser's notes move to the winner.
  Future<void> _resolveNameCollisions({String? fromPeer}) async {
    final byName = await _db.liveCategoriesByName();
    for (final entry in byName.entries) {
      final group = entry.value;
      if (group.length < 2) continue;
      final inbox = group.where((c) => c.id == Category.inboxId).toList();
      Category winner;
      if (inbox.isNotEmpty) {
        winner = inbox.first;
      } else {
        winner = group.reduce((a, b) => a.id.compareTo(b.id) <= 0 ? a : b);
      }
      for (final loser in group) {
        if (loser.id == winner.id) continue;
        final movedIds = await _db.itemIdsInCategory(loser.id);
        for (final itemId in movedIds) {
          final item = await _db.itemById(itemId);
          if (item == null) continue;
          final hlc = _clock.next().value;
          await _db.saveHlcValue(hlc);
          await _db.putItem(item.copyWith(categoryId: winner.id, metaHlc: hlc));
          await _db.appendChange(
            'item',
            itemId,
            sourcePeer: fromPeer,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );
        }
        final hlc = _clock.next().value;
        await _db.saveHlcValue(hlc);
        await _db.putCategory(loser.copyWith(deleted: true, metaHlc: hlc));
        await _db.appendChange('category', loser.id, sourcePeer: fromPeer);
        _logger.info(
          'merge: category name collision resolved',
          fields: {'loser': loser.id, 'winner': winner.id},
        );
      }
    }
  }

  // ---------------------------------------------------------------- peers ---

  /// Highest HLC observed in a page; the sync engine calls [HlcClock.observe]
  /// with it so later local events sort after every remote event (`SYNC-010`).
  static Hlc? maxHlcOfItem(Item item) {
    Hlc? max;
    for (final raw in [item.contentHlc, item.metaHlc, item.deletedHlc]) {
      final h = Hlc.tryParse(raw);
      if (h == null) continue;
      if (max == null || h.compareTo(max) > 0) max = h;
    }
    return max;
  }
}

/// Snapshot of the meta group for deterministic LWW merging.
class MetaGroup {
  const MetaGroup({
    this.categoryId,
    required this.pinned,
    required this.deleted,
    this.deletedHlc,
    required this.metaHlc,
  });

  final String? categoryId;
  final bool pinned;
  final bool deleted;
  final String? deletedHlc;
  final String metaHlc;

  factory MetaGroup.from(Item i) => MetaGroup(
    categoryId: i.categoryId,
    pinned: i.pinned,
    deleted: i.deleted,
    deletedHlc: i.deletedHlc,
    metaHlc: i.metaHlc,
  );

  /// Equal-HLC combination: survives if either side kept it.
  factory MetaGroup.combine(Item a, Item b) {
    final deleted = a.deleted && b.deleted;
    return MetaGroup(
      categoryId: _pickCategory(a.categoryId, b.categoryId),
      pinned: a.pinned && b.pinned,
      deleted: deleted,
      deletedHlc: deleted
          ? _maxHlcNullable(a.deletedHlc, b.deletedHlc)
          : _maxHlcNullable(a.deletedHlc, b.deletedHlc),
      metaHlc: a.metaHlc,
    );
  }

  static String? _pickCategory(String? a, String? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.compareTo(b) <= 0 ? a : b;
  }

  static String? _maxHlcNullable(String? a, String? b) {
    if (a == null) return b;
    if (b == null) return a;
    return compareHlcValues(a, b) >= 0 ? a : b;
  }
}

/// Compare two HLC strings; unparsable values sort before valid ones so a
/// malformed row can never win an LWW comparison. Never throws.
int compareHlcValues(String? a, String? b) {
  if (a == b) return 0;
  final ha = Hlc.tryParse(a);
  final hb = Hlc.tryParse(b);
  if (ha == null && hb == null) return (a ?? '').compareTo(b ?? '');
  if (ha == null) return -1;
  if (hb == null) return 1;
  return ha.compareTo(hb);
}
