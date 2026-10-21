import '../models/category.dart';
import '../models/change.dart';
import '../models/enums.dart';
import '../models/item.dart';
import '../models/peer.dart';
import 'database.dart';

/// Mappers between drift row classes and the pure domain models used by
/// services and the UI. Keep all enum parsing in one place.

extension ItemRowMapper on ItemRow {
  Item toDomain() => Item(
        id: id,
        type: ItemType.parse(type),
        kind: ItemKind.parse(kind),
        text: textBody,
        title: title,
        url: url,
        sourceApp: sourceApp,
        categoryId: categoryId,
        originDevice: originDevice,
        originName: originName,
        sourceItemId: sourceItemId,
        createdAt: createdAt,
        contentHash: contentHash,
        prevHash: prevHash,
        contentHlc: contentHlc,
        pinned: pinned,
        deleted: deleted,
        deletedHlc: deletedHlc,
        metaHlc: metaHlc,
        restored: restored,
        isConflictCopy: isConflictCopy,
      );
}

extension CategoryRowMapper on CategoryRow {
  Category toDomain() => Category(
        id: id,
        name: name,
        normalizedName: normalizedName,
        color: color,
        sortOrder: sortOrder,
        isInbox: isInbox,
        metaHlc: metaHlc,
        deleted: deleted,
      );
}

extension PeerRowMapper on PeerRow {
  Peer toDomain() => Peer(
        id: id,
        name: name,
        kind: PeerKind.parse(kind),
        roleOfPeer: PeerRole.parse(roleOfPeer),
        tokenHash: tokenHash,
        tokenRef: tokenRef,
        certFp: certFp,
        lastHost: lastHost,
        lastPort: lastPort,
        lastSeen: lastSeen,
        remoteSeq: remoteSeq,
        ackedSeq: ackedSeq,
        protocolVersion: protocolVersion,
        revokedAt: revokedAt,
        createdAt: createdAt,
      );
}

extension ChangeLogRowMapper on ChangeLogRow {
  ChangeEntry toDomain() => ChangeEntry(
        seq: seq,
        entityType: entityType,
        entityId: entityId,
        sourcePeer: sourcePeer,
        createdAt: createdAt,
      );
}

extension DeliveryRowMapper on PeerDeliveryRow {
  DeliveryInfo toDomain() => DeliveryInfo(
        peerId: peerId,
        itemId: itemId,
        state: DeliveryState.parse(state),
      );
}

extension QuarantineRowMapper on QuarantineRow {
  QuarantineEntry toDomain() => QuarantineEntry(
        id: id,
        peerId: peerId,
        entityType: entityType,
        entityId: entityId,
        reason: reason,
        payloadJson: payloadJson,
        receivedAt: receivedAt,
      );
}
