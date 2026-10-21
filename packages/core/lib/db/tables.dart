import 'package:drift/drift.dart';

/// SQLite schema for the local replica (`docs/04-data-model.md`).
///
/// Wire/domain models live in `lib/models/`; drift row classes are generated
/// with the `*Row` names to avoid clashing with them.

@DataClassName('PeerRow')
class Peers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get kind => text()();
  TextColumn get roleOfPeer => text()();
  TextColumn get tokenHash => text().nullable()();
  TextColumn get tokenRef => text().nullable()();
  TextColumn get certFp => text().nullable()();
  TextColumn get lastHost => text().nullable()();
  IntColumn get lastPort => integer().nullable()();
  IntColumn get lastSeen => integer().nullable()();
  IntColumn get remoteSeq => integer().withDefault(const Constant(0))();
  IntColumn get ackedSeq => integer().withDefault(const Constant(0))();
  IntColumn get protocolVersion => integer().withDefault(const Constant(1))();
  IntColumn get revokedAt => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get normalizedName => text()();
  TextColumn get color => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isInbox => boolean().withDefault(const Constant(false))();
  TextColumn get metaHlc => text()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ItemRow')
class Items extends Table {
  TextColumn get id => text()();
  TextColumn get type => text()();
  TextColumn get kind => text()();
  TextColumn get textBody => text().named('text')();
  TextColumn get title => text().nullable()();
  TextColumn get url => text().nullable()();
  TextColumn get sourceApp => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get originDevice => text()();
  TextColumn get originName => text()();
  TextColumn get sourceItemId => text().nullable()();
  IntColumn get createdAt => integer()();

  TextColumn get contentHash => text()();
  TextColumn get prevHash => text().nullable()();
  TextColumn get contentHlc => text()();

  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();
  TextColumn get deletedHlc => text().nullable()();
  TextColumn get metaHlc => text()();

  BoolColumn get restored => boolean().withDefault(const Constant(false))();
  BoolColumn get isConflictCopy =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ChangeLogRow')
class ChangeLogs extends Table {
  @override
  String get tableName => 'change_log';

  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get sourcePeer => text().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {seq};
}

@DataClassName('PeerDeliveryRow')
class PeerDeliveries extends Table {
  @override
  String get tableName => 'peer_delivery';

  TextColumn get peerId => text()();
  TextColumn get itemId => text()();
  TextColumn get state => text().withDefault(const Constant('queued'))();

  @override
  Set<Column> get primaryKey => {peerId, itemId};
}

@DataClassName('QuarantineRow')
class Quarantines extends Table {
  @override
  String get tableName => 'quarantine';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get peerId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get reason => text()();
  TextColumn get payloadJson => text()();
  IntColumn get receivedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AppliedRemoteRow')
class AppliedRemotes extends Table {
  @override
  String get tableName => 'applied_remote';

  TextColumn get peerId => text()();
  IntColumn get peerSeq => integer()();

  @override
  Set<Column> get primaryKey => {peerId, peerSeq};
}

@DataClassName('SettingRow')
class Settings extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
