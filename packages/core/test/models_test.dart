import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';

import 'support/test_support.dart';

void main() {
  group('Item', () {
    Item sample() => makeItem(
      id: testUuid(1),
      text: 'hello',
      title: 'Title',
      url: 'https://example.com',
      categoryId: Category.inboxId,
      sourceApp: 'com.android.chrome',
      contentHlc: hlcValue(1000, 1, 'a'),
      prevHash: 'a' * 64,
      pinned: true,
      deleted: true,
      deletedHlc: hlcValue(2000, 1, 'a'),
      restored: true,
      isConflictCopy: true,
    );

    test('round-trips through JSON', () {
      final item = sample();
      final decoded = Item.fromJson(item.toJson());
      expect(decoded.id, item.id);
      expect(decoded.type, item.type);
      expect(decoded.kind, item.kind);
      expect(decoded.text, item.text);
      expect(decoded.title, item.title);
      expect(decoded.url, item.url);
      expect(decoded.sourceApp, item.sourceApp);
      expect(decoded.categoryId, item.categoryId);
      expect(decoded.originDevice, item.originDevice);
      expect(decoded.originName, item.originName);
      expect(decoded.createdAt, item.createdAt);
      expect(decoded.contentHash, item.contentHash);
      expect(decoded.prevHash, item.prevHash);
      expect(decoded.contentHlc, item.contentHlc);
      expect(decoded.pinned, isTrue);
      expect(decoded.deleted, isTrue);
      expect(decoded.deletedHlc, item.deletedHlc);
      expect(decoded.metaHlc, item.metaHlc);
      expect(decoded.restored, isTrue);
      expect(decoded.isConflictCopy, isTrue);
    });

    test('omits the optional fields when they are null', () {
      final item = makeItem(
        id: testUuid(2),
        text: 'plain',
        contentHlc: hlcValue(1000, 1, 'a'),
      );
      final json = item.toJson();
      expect(json.containsKey('title'), isFalse);
      expect(json.containsKey('url'), isFalse);
      expect(json.containsKey('categoryId'), isFalse);
      expect(json.containsKey('prevHash'), isFalse);
      expect(json.containsKey('deletedHlc'), isFalse);
    });

    test('copyWith can clear the optional fields', () {
      final item = sample();
      final cleared = item.copyWith(clearTitle: true, clearUrl: true);
      expect(cleared.title, isNull);
      expect(cleared.url, isNull);
      final withoutDeleted = item.copyWith(clearDeletedHlc: true);
      expect(withoutDeleted.deletedHlc, isNull);
    });

    test('exposes the type helpers', () {
      expect(sample().isNote, isTrue);
      expect(sample().isMessage, isFalse);
      expect(sample().isLink, isTrue);
    });
  });

  group('Category', () {
    test('round-trips through JSON', () {
      final category = makeCategory(
        id: testUuid(3),
        name: 'Research',
        metaHlc: hlcValue(1000, 1, 'a'),
        color: '#ff0000',
      );
      final decoded = Category.fromJson(category.toJson());
      expect(decoded.id, category.id);
      expect(decoded.name, category.name);
      expect(decoded.normalizedName, category.normalizedName);
      expect(decoded.color, category.color);
      expect(decoded.sortOrder, category.sortOrder);
      expect(decoded.isInbox, category.isInbox);
      expect(decoded.metaHlc, category.metaHlc);
      expect(decoded.deleted, category.deleted);
    });

    test('copyWith can clear the colour', () {
      final category = makeCategory(
        id: testUuid(4),
        name: 'Research',
        metaHlc: hlcValue(1000, 1, 'a'),
        color: '#ff0000',
      );
      expect(category.copyWith(clearColor: true).color, isNull);
    });

    test('the Inbox constants are fixed', () {
      expect(Category.inboxId, 'inbox');
      expect(Category.inboxName, 'Inbox');
    });
  });

  group('Peer', () {
    test('serialises the safe fields', () {
      final peer = makePeer(
        id: testUuid(5),
        tokenHash: 'a' * 64,
        certFp: 'b' * 64,
      );
      final json = peer.toJson();
      expect(json['id'], peer.id);
      expect(json['name'], peer.name);
      expect(json['kind'], peer.kind.wire);
      expect(json['roleOfPeer'], peer.roleOfPeer.wire);
      expect(json['remoteSeq'], peer.remoteSeq);
      expect(json['ackedSeq'], peer.ackedSeq);
      expect(json['protocolVersion'], peer.protocolVersion);
      expect(json['createdAt'], peer.createdAt);
    });

    test('never serialises the token hash or the pin', () {
      final peer = makePeer(id: testUuid(6), tokenHash: 'a' * 64);
      final json = peer.toJson();
      expect(json.containsKey('tokenHash'), isFalse);
      expect(json.containsKey('certFp'), isFalse);
      expect(json.values.map((v) => '$v').join(), isNot(contains('a' * 64)));
    });

    test('isRevoked follows revokedAt', () {
      expect(makePeer(id: testUuid(7)).isRevoked, isFalse);
      expect(makePeer(id: testUuid(8), revokedAt: 1000).isRevoked, isTrue);
    });

    test('copyWith can clear the revoked marker', () {
      final peer = makePeer(id: testUuid(9), revokedAt: 1000);
      expect(peer.copyWith(clearRevokedAt: true).isRevoked, isFalse);
    });

    test('copyWith keeps the token hash when null is passed', () {
      // KNOWN QUIRK: `Peer.copyWith` uses `tokenHash ?? this.tokenHash`, so
      // `copyWith(tokenHash: null)` does NOT clear the hash. `PeerRegistry
      // .revoke()` relies on that call, so the desktop keeps the phone's
      // token hash after a revoke. Reported as a finding.
      final peer = makePeer(id: testUuid(10), tokenHash: 'a' * 64);
      expect(peer.copyWith(tokenHash: null).tokenHash, 'a' * 64);
    });
  });

  group('enums', () {
    test('the wire names round-trip', () {
      for (final value in ItemType.values) {
        expect(ItemType.parse(value.wire), value);
      }
      for (final value in ItemKind.values) {
        expect(ItemKind.parse(value.wire), value);
      }
      for (final value in DeliveryState.values) {
        expect(DeliveryState.parse(value.wire), value);
      }
      for (final value in PeerKind.values) {
        expect(PeerKind.parse(value.wire), value);
      }
      for (final value in PeerRole.values) {
        expect(PeerRole.parse(value.wire), value);
      }
      for (final value in PairingState.values) {
        expect(PairingState.parse(value.wire), value);
      }
      for (final value in QuarantineReason.values) {
        expect(QuarantineReason.parse(value.wire), value);
      }
      for (final value in ShareDefaultAction.values) {
        expect(ShareDefaultAction.parse(value.wire), value);
      }
      for (final value in AppThemeChoice.values) {
        expect(AppThemeChoice.parse(value.wire), value);
      }
    });

    test('an unknown wire name throws', () {
      expect(() => ItemType.parse('nope'), throwsFormatException);
      expect(() => ItemKind.parse('nope'), throwsFormatException);
      expect(() => DeliveryState.parse('nope'), throwsFormatException);
      expect(() => PeerKind.parse('nope'), throwsFormatException);
      expect(() => PairingState.parse('nope'), throwsFormatException);
    });

    test('an unknown share action falls back to the notepad', () {
      expect(ShareDefaultAction.parse('nope'), ShareDefaultAction.notepad);
    });

    test('an unknown quarantine reason falls back to validation_failed', () {
      expect(QuarantineReason.parse('nope'), QuarantineReason.validationFailed);
    });

    test('the connection status helpers', () {
      expect(ConnectionStatus.connected.isOnline, isTrue);
      expect(ConnectionStatus.syncing.isOnline, isTrue);
      expect(ConnectionStatus.offline.isOnline, isFalse);
      expect(ConnectionStatus.paused.isOnline, isFalse);
    });
  });

  group('errors', () {
    test('every error carries a stable code and HTTP status', () {
      expect(const ValidationError('x').code, ErrorCodes.validationError);
      expect(const ValidationError('x').httpStatus, 400);
      expect(const UnauthorizedError().code, ErrorCodes.unauthorized);
      expect(const UnauthorizedError().httpStatus, 401);
      expect(const ForbiddenError().code, ErrorCodes.forbidden);
      expect(const ForbiddenError().httpStatus, 403);
      expect(const NotFoundError().code, ErrorCodes.notFound);
      expect(const NotFoundError().httpStatus, 404);
      expect(const PayloadTooLargeError('x').code, ErrorCodes.payloadTooLarge);
      expect(const PayloadTooLargeError('x').httpStatus, 413);
      expect(const RateLimitedError().code, ErrorCodes.rateLimited);
      expect(const RateLimitedError().httpStatus, 429);
      expect(const PairingFailedError().code, ErrorCodes.pairingFailed);
      expect(
        const PairingFailedError(expired: true).code,
        ErrorCodes.pairingExpired,
      );
      expect(
        const CertificateMismatchError().code,
        ErrorCodes.certificateMismatch,
      );
      expect(
        const UnsupportedVersionError('x').code,
        ErrorCodes.unsupportedVersion,
      );
      expect(const UnsupportedVersionError('x').httpStatus, 426);
      expect(const NetworkError('x').code, ErrorCodes.networkError);
      expect(const StorageError('x').code, ErrorCodes.storageError);
      expect(const StorageError('x').httpStatus, 500);
      expect(const InternalError('x').code, ErrorCodes.internalError);
      expect(const ServerShutdownError().code, ErrorCodes.serverShutdown);
      expect(const ProtocolError('x').code, ErrorCodes.validationError);
    });

    test('the retryable flag', () {
      expect(const NetworkError('x').retryable, isTrue);
      expect(const RateLimitedError().retryable, isTrue);
      expect(const ServerShutdownError().retryable, isTrue);
      expect(const ValidationError('x').retryable, isFalse);
      expect(const UnauthorizedError().retryable, isFalse);
    });

    test('the message never leaks a payload', () {
      expect(const ValidationError('bad').message, 'bad');
      expect(
        const CertificateMismatchError().message.toLowerCase(),
        isNot(contains('token')),
      );
    });
  });

  group('change models', () {
    test('DeliveryInfo copyWith', () {
      const info = DeliveryInfo(
        peerId: 'p',
        itemId: 'i',
        state: DeliveryState.queued,
      );
      expect(
        info.copyWith(state: DeliveryState.sent).state,
        DeliveryState.sent,
      );
      expect(info.copyWith().state, DeliveryState.queued);
    });

    test('ChangeEntry keeps the source peer', () {
      const entry = ChangeEntry(
        seq: 1,
        entityType: 'item',
        entityId: 'i',
        createdAt: 1000,
      );
      expect(entry.sourcePeer, isNull);
      expect(entry.entityType, 'item');
      expect(entry.toJson()['seq'], 1);
    });
  });

  group('stores', () {
    test('the memory token store round-trips a token', () async {
      final store = MemoryTokenStore();
      expect(await store.read('ref'), isNull);
      await store.write('ref', 'value');
      expect(await store.read('ref'), 'value');
      await store.delete('ref');
      expect(await store.read('ref'), isNull);
    });

    test('the peer token ref is stable and namespaced', () {
      expect(peerTokenRef('abc'), 'peer.abc.token');
    });

    test('the no-op implementations do nothing', () async {
      final notifier = NoopNotifier();
      await notifier.onConnectionChanged(ConnectionStatus.connected);
      await notifier.clear();
      final lock = NoopMulticastLock();
      await lock.acquire();
      await lock.release();
    });
  });
}
