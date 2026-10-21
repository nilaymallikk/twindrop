/// Shared enums and small value types for TwinDrop.
///
/// Wire names are part of the on-disk change log and the WS protocol: never
/// rename an existing value without a schema/protocol version bump.
library;

enum ItemType {
  message('message'),
  note('note');

  const ItemType(this.wire);
  final String wire;
  static ItemType parse(String v) => values.firstWhere(
        (e) => e.wire == v,
        orElse: () => throw FormatException('unknown item type: $v'),
      );
}

enum ItemKind {
  text('text'),
  link('link');

  const ItemKind(this.wire);
  final String wire;
  static ItemKind parse(String v) => values.firstWhere(
        (e) => e.wire == v,
        orElse: () => throw FormatException('unknown item kind: $v'),
      );
}

/// Message delivery vocabulary (`docs/05`): Queued -> Sent -> Delivered.
/// `Sent` means written to the socket; `Delivered` requires a peer ack.
enum DeliveryState {
  queued('queued'),
  sent('sent'),
  delivered('delivered');

  const DeliveryState(this.wire);
  final String wire;
  static DeliveryState parse(String v) => values.firstWhere(
        (e) => e.wire == v,
        orElse: () => throw FormatException('unknown delivery state: $v'),
      );
}

/// Visible connection state (PAIR-006). `paused` is desktop-specific.
enum ConnectionStatus {
  unpaired('unpaired'),
  pairing('pairing'),
  searching('searching'),
  connecting('connecting'),
  connected('connected'),
  syncing('syncing'),
  offline('offline'),
  paused('paused'),
  removed('removed');

  const ConnectionStatus(this.wire);
  final String wire;

  bool get isOnline => this == connected || this == syncing;
}

enum PeerKind {
  phone('phone'),
  desktop('desktop');

  const PeerKind(this.wire);
  final String wire;
  static PeerKind parse(String v) => values.firstWhere(
        (e) => e.wire == v,
        orElse: () => throw FormatException('unknown peer kind: $v'),
      );
}

enum PeerRole {
  host('host'),
  guest('guest');

  const PeerRole(this.wire);
  final String wire;
  static PeerRole parse(String v) => values.firstWhere(
        (e) => e.wire == v,
        orElse: () => throw FormatException('unknown peer role: $v'),
      );
}

/// Default action after Android share (`SHARE-004`).
enum ShareDefaultAction {
  notepad('notepad'),
  chat('chat'),
  ask('ask');

  const ShareDefaultAction(this.wire);
  final String wire;
  static ShareDefaultAction parse(String v) => values.firstWhere(
        (e) => e.wire == v,
        orElse: () => ShareDefaultAction.notepad,
      );
}

enum AppThemeChoice {
  dark('dark'),
  light('light'),
  system('system'),
  black('black');

  const AppThemeChoice(this.wire);
  final String wire;
  static AppThemeChoice parse(String v) => values.firstWhere(
        (e) => e.wire == v,
        orElse: () => AppThemeChoice.dark,
      );
}

/// Pairing session / request state (`docs/05`).
enum PairingState {
  pendingApproval('pending_approval'),
  approved('approved'),
  rejected('rejected'),
  expired('expired');

  const PairingState(this.wire);
  final String wire;
  static PairingState parse(String v) => values.firstWhere(
        (e) => e.wire == v,
        orElse: () => throw FormatException('unknown pairing state: $v'),
      );
}

/// Why a remote change was quarantined (SYNC-006).
enum QuarantineReason {
  invalidUrl('invalid_url'),
  oversize('oversize'),
  malformed('malformed'),
  unknownEntity('unknown_entity'),
  validationFailed('validation_failed'),
  unsupportedVersion('unsupported_version');

  const QuarantineReason(this.wire);
  final String wire;
  static QuarantineReason parse(String v) => values.firstWhere(
        (e) => e.wire == v,
        orElse: () => QuarantineReason.validationFailed,
      );
}
