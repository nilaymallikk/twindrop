import 'enums.dart';

/// One row of the local change log. Every local write and every applied remote
/// write appends a row so it can propagate to other peers (SYNC-002).
class ChangeEntry {
  const ChangeEntry({
    required this.seq,
    required this.entityType,
    required this.entityId,
    this.sourcePeer,
    required this.createdAt,
  });

  final int seq;

  /// `item` or `category`.
  final String entityType;
  final String entityId;

  /// null = local origin; otherwise the peer we received the change from.
  final String? sourcePeer;
  final int createdAt;

  static const String entityItem = 'item';
  static const String entityCategory = 'category';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'seq': seq,
    'entityType': entityType,
    'entityId': entityId,
    if (sourcePeer != null) 'sourcePeer': sourcePeer,
    'createdAt': createdAt,
  };
}

/// Local-only delivery state for a message sent to one peer (`peer_delivery`).
class DeliveryInfo {
  const DeliveryInfo({
    required this.peerId,
    required this.itemId,
    required this.state,
  });

  final String peerId;
  final String itemId;
  final DeliveryState state;

  DeliveryInfo copyWith({DeliveryState? state}) =>
      DeliveryInfo(peerId: peerId, itemId: itemId, state: state ?? this.state);
}

/// A remote change that failed validation and is kept visible instead of being
/// silently dropped (SYNC-006). Viewable in Settings -> Data.
class QuarantineEntry {
  const QuarantineEntry({
    required this.id,
    required this.peerId,
    required this.entityType,
    required this.entityId,
    required this.reason,
    required this.payloadJson,
    required this.receivedAt,
  });

  final int id;
  final String peerId;
  final String entityType;
  final String entityId;
  final String reason;
  final String payloadJson;
  final int receivedAt;
}
