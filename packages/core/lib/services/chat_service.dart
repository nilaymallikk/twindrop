import '../db/store_ops.dart';
import '../models/change.dart';
import '../models/enums.dart';
import '../models/errors.dart';
import '../models/item.dart';
import '../sync/change_bus.dart';
import '../util/hlc.dart';
import '../util/logger.dart';
import 'item_builder.dart';
import 'peer_registry.dart';
import 'service_base.dart';
import '../db/database.dart';

/// Chat messages: immutable content, delivery states driven only by acks.
///
/// A message is written locally together with a `change_log` row and one
/// `peer_delivery(queued)` row per paired peer before any network call
/// (`MSG-005`). `queued -> sent -> delivered`; only an ack from the peer can
/// produce `delivered` (`MSG-006`).
class ChatService extends CoreService {
  ChatService({
    required super.db,
    required super.clock,
    required super.bus,
    required super.logger,
    required PeerRegistry peers,
    required String deviceId,
    required String deviceName,
    bool Function()? cleanLinks,
    super.nowMs,
  })  : _peers = peers,
        _deviceId = deviceId,
        _deviceName = deviceName,
        _cleanLinks = cleanLinks ?? (() => true);

  final PeerRegistry _peers;
  final String _deviceId;
  final String _deviceName;
  final bool Function() _cleanLinks;

  /// Persist a message locally, queue it for every paired peer, then signal
  /// sync. Returns the stored item with its delivery rows already queued.
  Future<Item> sendMessage(String text, {String? sourceApp}) async {
    final prepared = buildNewItem(
      type: ItemType.message,
      text: text,
      sourceApp: sourceApp,
      deviceId: _deviceId,
      deviceName: _deviceName,
      hlc: '', // replaced inside the transaction
      createdAt: nowMs(),
      cleanInstagramLinks: _cleanLinks(),
    );
    late Item saved;
    await db.transaction(() async {
      final hlc = await stamp();
      saved = buildNewItem(
        id: prepared.id,
        type: ItemType.message,
        text: text,
        sourceApp: sourceApp,
        deviceId: _deviceId,
        deviceName: _deviceName,
        hlc: hlc,
        createdAt: prepared.createdAt,
        cleanInstagramLinks: _cleanLinks(),
      );
      await db.putItem(saved);
      await db.ftsUpsert(saved);
      await db.appendChange('item', saved.id);
      final peers = await _peers.active();
      for (final peer in peers) {
        await db.createQueuedDelivery(peer.id, saved.id);
      }
    });
    notifyChanged();
    logger.info('message queued', fields: {'id': saved.id});
    return saved;
  }

  /// Newest-first message history with keyset pagination (`beforeCreatedAt` +
  /// `beforeId` from the last item of the previous page).
  Future<List<Item>> listMessages({
    int limit = 50,
    int? beforeCreatedAt,
    String? beforeId,
    bool includeDeleted = false,
  }) =>
      db.listItems(
        type: ItemType.message,
        limit: limit,
        beforeCreatedAt: beforeCreatedAt,
        beforeId: beforeId,
        includeDeleted: includeDeleted,
      );

  Stream<List<Item>> watchMessages({int limit = 100}) async* {
    yield await listMessages(limit: limit);
    await for (final _ in bus.stream) {
      yield await listMessages(limit: limit);
    }
  }

  Future<Item?> messageById(String id) async {
    final item = await db.itemById(id);
    if (item == null || item.type != ItemType.message) return null;
    return item;
  }

  Future<List<DeliveryInfo>> deliveryFor(String itemId) =>
      db.deliveriesForItem(itemId);

  /// Delete is the only mutation a message allows (content is immutable,
  /// `docs/04`).
  Future<Item> deleteMessage(String id) async {
    final item = await db.itemById(id);
    if (item == null || item.type != ItemType.message) {
      throw const NotFoundError('message not found');
    }
    late Item updated;
    await db.transaction(() async {
      final hlc = await stamp();
      updated = item.copyWith(
        deleted: true,
        deletedHlc: hlc,
        metaHlc: hlc,
      );
      await db.putItem(updated);
      await db.ftsRemove(id);
      await db.appendChange('item', id);
    });
    notifyChanged();
    return updated;
  }

  /// "Save to Notepad" (`MSG-007`, `NOTE-004`): copies the message into a note,
  /// links back via `sourceItemId`.
  Future<Item> saveMessageAsNote(
    String messageId, {
    String? categoryId,
    String? noteTitle,
  }) async {
    final message = await messageById(messageId);
    if (message == null) throw const NotFoundError('message not found');
    final targetCategory = categoryId ?? 'inbox';
    final category = await db.categoryById(targetCategory);
    if (category == null || category.deleted) {
      throw const ValidationError('unknown category');
    }
    late Item note;
    await db.transaction(() async {
      final hlc = await stamp();
      note = buildNewItem(
        type: ItemType.note,
        text: message.text,
        title: noteTitle,
        categoryId: targetCategory,
        sourceApp: message.sourceApp,
        sourceItemId: message.id,
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

  /// Rebuild the notepad service's clock after a restart — kept here only as a
  /// reminder that HLC state lives in settings, not in the service.
  Future<String?> persistedHlc() => db.lastHlcValue();

  /// Convenience for callers constructing a HlcClock after restart.
  static Hlc? lastHlcFrom(String? raw) => Hlc.tryParse(raw);

  /// Access to the bus for the UI facade.
  ChangeBus get changeBus => bus;

  /// AppDatabase accessor (facade wiring).
  AppDatabase get database => db;
}
