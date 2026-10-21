import 'dart:math';

import '../db/database.dart';
import '../db/store_ops.dart';
import '../models/category.dart';
import '../models/enums.dart';
import '../models/errors.dart';
import '../models/item.dart';
import '../util/ids.dart';
import '../util/logger.dart';
import '../validators/validators.dart';
import 'item_builder.dart';
import 'service_base.dart';

/// Notepad: categories (with fixed Inbox protection) and notes with a content
/// group that can be edited offline and merged deterministically (`NOTE-*`).
class NotepadService extends CoreService {
  NotepadService({
    required super.db,
    required super.clock,
    required super.bus,
    required super.logger,
    required String deviceId,
    required String deviceName,
    bool Function()? cleanLinks,
    super.nowMs,
  }) : _deviceId = deviceId,
       _deviceName = deviceName,
       _cleanLinks = cleanLinks ?? (() => true);

  final String _deviceId;
  final String _deviceName;
  final bool Function() _cleanLinks;

  // ----------------------------------------------------------- categories ---

  /// Create the fixed Inbox row if missing (`NOTE-002`). Idempotent; called on
  /// every startup.
  Future<Category> ensureInbox() async {
    final existing = await db.categoryById(Category.inboxId);
    if (existing != null) {
      if (existing.deleted || !existing.isInbox) {
        // Repair a tombstoned/incoherent Inbox row.
        final repaired = existing.copyWith(
          name: Category.inboxName,
          normalizedName: Category.inboxName.toLowerCase(),
          deleted: false,
        );
        await db.putCategory(repaired);
        return repaired;
      }
      return existing;
    }
    late Category inbox;
    await db.transaction(() async {
      final hlc = await stamp();
      inbox = Category(
        id: Category.inboxId,
        name: Category.inboxName,
        normalizedName: Category.inboxName.toLowerCase(),
        sortOrder: 0,
        isInbox: true,
        metaHlc: hlc,
        deleted: false,
      );
      await db.putCategory(inbox);
      await db.appendChange('category', inbox.id);
    });
    notifyChanged();
    return inbox;
  }

  Future<List<Category>> listCategories({bool includeDeleted = false}) =>
      db.listCategoryRows(includeDeleted: includeDeleted);

  Future<Category?> getCategory(String id) => db.categoryById(id);

  Stream<List<Category>> watchCategories() async* {
    yield await listCategories();
    await for (final _ in bus.stream) {
      yield await listCategories();
    }
  }

  Future<Category> createCategory(String name, {String? color}) async {
    validateCategoryName(name);
    final normalized = normalizeCategoryName(name);
    if (normalized == Category.inboxName.toLowerCase()) {
      throw const ValidationError('Inbox is reserved');
    }
    final existing = await listCategories();
    if (existing.any((c) => c.normalizedName == normalized)) {
      throw const ValidationError('category name already exists');
    }
    final sortOrder = existing.isEmpty
        ? 1
        : existing.map((c) => c.sortOrder).reduce(max) + 1;
    late Category created;
    await db.transaction(() async {
      final hlc = await stamp();
      created = Category(
        id: newId(),
        name: name.trim().replaceAll(RegExp(r'\s+'), ' '),
        normalizedName: normalized,
        color: color,
        sortOrder: sortOrder,
        isInbox: false,
        metaHlc: hlc,
        deleted: false,
      );
      await db.putCategory(created);
      await db.appendChange('category', created.id);
    });
    notifyChanged();
    return created;
  }

  Future<Category> renameCategory(String id, String name) async {
    final category = await _requireCategory(id);
    if (category.isInbox) {
      throw const ForbiddenError('Inbox cannot be renamed');
    }
    validateCategoryName(name);
    final normalized = normalizeCategoryName(name);
    if (normalized == Category.inboxName.toLowerCase()) {
      throw const ValidationError('Inbox is reserved');
    }
    final others = await listCategories();
    if (others.any((c) => c.id != id && c.normalizedName == normalized)) {
      throw const ValidationError('category name already exists');
    }
    late Category updated;
    await db.transaction(() async {
      final hlc = await stamp();
      updated = category.copyWith(
        name: name.trim().replaceAll(RegExp(r'\s+'), ' '),
        normalizedName: normalized,
        metaHlc: hlc,
      );
      await db.putCategory(updated);
      await db.appendChange('category', id);
    });
    notifyChanged();
    return updated;
  }

  /// Persist a new visual order; [orderedIds] must be a permutation of the
  /// live categories (unknown ids are ignored, missing ones keep their order).
  Future<List<Category>> reorderCategories(List<String> orderedIds) async {
    final categories = await listCategories();
    final byId = {for (final c in categories) c.id: c};
    final order = <Category>[];
    for (final id in orderedIds) {
      final c = byId.remove(id);
      if (c != null) order.add(c);
    }
    order.addAll(byId.values);
    await db.transaction(() async {
      for (var i = 0; i < order.length; i++) {
        final c = order[i];
        final hlc = await stamp();
        await db.putCategory(c.copyWith(sortOrder: i, metaHlc: hlc));
        await db.appendChange('category', c.id);
      }
    });
    notifyChanged();
    return listCategories();
  }

  /// Delete a category: move its notes to Inbox first, then tombstone the
  /// category (`docs/04` rule 6). Never cascades (`NOTE-001`).
  Future<void> deleteCategory(String id) async {
    final category = await _requireCategory(id);
    if (category.isInbox || id == Category.inboxId) {
      throw const ForbiddenError('Inbox cannot be deleted');
    }
    await ensureInbox();
    await db.transaction(() async {
      final noteIds = await db.itemIdsInCategory(id);
      for (final noteId in noteIds) {
        final note = await db.itemById(noteId);
        if (note == null) continue;
        final hlc = await stamp();
        await db.putItem(
          note.copyWith(categoryId: Category.inboxId, metaHlc: hlc),
        );
        await db.appendChange('item', noteId);
      }
      final hlc = await stamp();
      await db.putCategory(category.copyWith(deleted: true, metaHlc: hlc));
      await db.appendChange('category', id);
    });
    notifyChanged();
    logger.info('category deleted', fields: {'id': id});
  }

  // ---------------------------------------------------------------- notes ---

  Future<Item> createNote({
    String text = '',
    String? title,
    String? url,
    String? categoryId,
    String? sourceApp,
    String? sourceItemId,
  }) async {
    final target = categoryId ?? Category.inboxId;
    final category = await db.categoryById(target);
    if (category == null || category.deleted) {
      throw const ValidationError('unknown category');
    }
    late Item note;
    await db.transaction(() async {
      final hlc = await stamp();
      note = buildNewItem(
        type: ItemType.note,
        text: text,
        title: title,
        url: url,
        categoryId: target,
        sourceApp: sourceApp,
        sourceItemId: sourceItemId,
        deviceId: _deviceId,
        deviceName: _deviceName,
        hlc: hlc,
        createdAt: nowMs(),
        cleanInstagramLinks: _cleanLinks(),
      );
      await db.putItem(note);
      await db.ftsUpsert(note);
      await db.appendChange('item', note.id);
    });
    notifyChanged();
    return note;
  }

  /// Edit the content group; the old content stays recoverable as `prev_hash`
  /// chain and a concurrent edit produces a conflict copy on merge.
  Future<Item> updateNote(
    String id, {
    String? text,
    String? title,
    String? url,
    bool clearTitle = false,
    bool clearUrl = false,
  }) async {
    final note = await _requireNote(id);
    late Item updated;
    await db.transaction(() async {
      final hlc = await stamp();
      updated = editedContent(
        note,
        text: text,
        title: title,
        url: url,
        clearTitle: clearTitle,
        clearUrl: clearUrl,
        hlc: hlc,
        cleanInstagramLinks: _cleanLinks(),
      );
      await db.putItem(updated);
      await db.ftsUpsert(updated);
      await db.appendChange('item', id);
    });
    notifyChanged();
    return updated;
  }

  Future<Item> pinNote(String id, bool pinned) async {
    final note = await _requireNote(id);
    if (note.pinned == pinned) return note;
    late Item updated;
    await db.transaction(() async {
      final hlc = await stamp();
      updated = note.copyWith(pinned: pinned, metaHlc: hlc);
      await db.putItem(updated);
      await db.appendChange('item', id);
    });
    notifyChanged();
    return updated;
  }

  Future<Item> moveNote(String id, String categoryId) async {
    final note = await _requireNote(id);
    final category = await db.categoryById(categoryId);
    if (category == null || category.deleted) {
      throw const ValidationError('unknown category');
    }
    if (note.categoryId == categoryId) return note;
    late Item updated;
    await db.transaction(() async {
      final hlc = await stamp();
      updated = note.copyWith(categoryId: categoryId, metaHlc: hlc);
      await db.putItem(updated);
      await db.appendChange('item', id);
    });
    notifyChanged();
    return updated;
  }

  /// Tombstone a note (Undo is [restoreNote]). Content stays in the replica so
  /// a concurrent edit can win it back (`docs/04` rule 4).
  Future<Item> deleteNote(String id) async {
    final note = await _requireNote(id);
    late Item updated;
    await db.transaction(() async {
      final hlc = await stamp();
      updated = note.copyWith(deleted: true, deletedHlc: hlc, metaHlc: hlc);
      await db.putItem(updated);
      await db.ftsRemove(id);
      await db.appendChange('item', id);
    });
    notifyChanged();
    return updated;
  }

  /// Undo a delete (new meta HLC, so it wins LWW over the old tombstone).
  Future<Item> restoreNote(String id) async {
    final note = await _requireNote(id, includeDeleted: true);
    if (!note.deleted) return note;
    late Item updated;
    await db.transaction(() async {
      final hlc = await stamp();
      updated = note.copyWith(deleted: false, metaHlc: hlc);
      await db.putItem(updated);
      await db.ftsUpsert(updated);
      await db.appendChange('item', id);
    });
    notifyChanged();
    return updated;
  }

  Future<List<Item>> listNotes({
    String? categoryId,
    int limit = 200,
    bool includeDeleted = false,
    bool onlyDeleted = false,
  }) => db.listItems(
    type: ItemType.note,
    categoryId: categoryId,
    limit: limit,
    includeDeleted: includeDeleted,
    onlyDeleted: onlyDeleted,
  );

  Stream<List<Item>> watchNotes({String? categoryId, int limit = 200}) async* {
    yield await listNotes(categoryId: categoryId, limit: limit);
    await for (final _ in bus.stream) {
      yield await listNotes(categoryId: categoryId, limit: limit);
    }
  }

  /// Recent-deleted list for Undo UI.
  Future<List<Item>> recentlyDeleted({int limit = 50}) =>
      listNotes(onlyDeleted: true, includeDeleted: true, limit: limit);

  /// FTS over title/text/url restricted to notes, optionally by category
  /// (`NOTE-006`, < 100 ms at 10k notes).
  Future<List<Item>> search(
    String query, {
    String? categoryId,
    int limit = 100,
  }) async {
    if (query.trim().isEmpty) {
      return listNotes(categoryId: categoryId, limit: limit);
    }
    final ids = await db.ftsSearchIds(query, limit: limit * 2);
    if (ids.isEmpty) return const [];
    final out = <Item>[];
    for (final id in ids) {
      final item = await db.itemById(id);
      if (item == null) continue;
      if (item.type != ItemType.note || item.deleted) continue;
      if (categoryId != null && item.categoryId != categoryId) continue;
      out.add(item);
      if (out.length >= limit) break;
    }
    return out;
  }

  Future<List<Item>> listConflictCopies({int limit = 100}) async {
    final notes = await listNotes(limit: 1000);
    return notes.where((n) => n.isConflictCopy).take(limit).toList();
  }

  Future<Item?> getNote(String id) async {
    final item = await db.itemById(id);
    if (item == null || item.type != ItemType.note) return null;
    return item;
  }

  Future<Category> _requireCategory(String id) async {
    final category = await db.categoryById(id);
    if (category == null) throw const NotFoundError('category not found');
    return category;
  }

  Future<Item> _requireNote(String id, {bool includeDeleted = false}) async {
    final note = await getNote(id);
    if (note == null) throw const NotFoundError('note not found');
    if (note.deleted && !includeDeleted) {
      throw const NotFoundError('note not found');
    }
    return note;
  }

  /// Export helper: every note in a category, oldest first, including the
  /// conflict copies (flagged).
  Future<List<Item>> notesForExport({String? categoryId}) async {
    final notes = await listNotes(categoryId: categoryId, limit: 10000);
    return notes.reversed.toList(growable: false);
  }
}
