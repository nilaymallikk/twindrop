import 'enums.dart';

/// A paired device. On the desktop, `tokenHash` holds `sha256(deviceToken)` for
/// the phone; on the phone `tokenRef` names the key in secure storage and the
/// token itself never touches SQLite (PAIR-004).
class Peer {
  const Peer({
    required this.id,
    required this.name,
    required this.kind,
    required this.roleOfPeer,
    this.tokenHash,
    this.tokenRef,
    this.certFp,
    this.lastHost,
    this.lastPort,
    this.lastSeen,
    this.remoteSeq = 0,
    this.ackedSeq = 0,
    this.protocolVersion = 1,
    this.revokedAt,
    required this.createdAt,
  });

  /// Remote device id.
  final String id;
  final String name;
  final PeerKind kind;
  final PeerRole roleOfPeer;

  /// Desktop side only: SHA-256 hex of the phone's device token.
  final String? tokenHash;

  /// Phone side only: secure-storage key holding the device token.
  final String? tokenRef;

  /// Pinned certificate fingerprint (SHA-256 hex of DER) for this host.
  final String? certFp;
  final String? lastHost;
  final int? lastPort;
  final int? lastSeen;

  /// Highest peer change-log seq applied locally.
  final int remoteSeq;

  /// Highest of OUR seq the peer acknowledged.
  final int ackedSeq;
  final int protocolVersion;
  final int? revokedAt;
  final int createdAt;

  bool get isRevoked => revokedAt != null;

  Peer copyWith({
    String? name,
    PeerKind? kind,
    PeerRole? roleOfPeer,
    String? tokenHash,
    String? tokenRef,
    String? certFp,
    String? lastHost,
    int? lastPort,
    int? lastSeen,
    int? remoteSeq,
    int? ackedSeq,
    int? protocolVersion,
    int? revokedAt,
    bool clearRevokedAt = false,
  }) =>
      Peer(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        roleOfPeer: roleOfPeer ?? this.roleOfPeer,
        tokenHash: tokenHash ?? this.tokenHash,
        tokenRef: tokenRef ?? this.tokenRef,
        certFp: certFp ?? this.certFp,
        lastHost: lastHost ?? this.lastHost,
        lastPort: lastPort ?? this.lastPort,
        lastSeen: lastSeen ?? this.lastSeen,
        remoteSeq: remoteSeq ?? this.remoteSeq,
        ackedSeq: ackedSeq ?? this.ackedSeq,
        protocolVersion: protocolVersion ?? this.protocolVersion,
        revokedAt: clearRevokedAt ? null : (revokedAt ?? this.revokedAt),
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'kind': kind.wire,
        'roleOfPeer': roleOfPeer.wire,
        if (lastHost != null) 'lastHost': lastHost,
        if (lastPort != null) 'lastPort': lastPort,
        if (lastSeen != null) 'lastSeen': lastSeen,
        'remoteSeq': remoteSeq,
        'ackedSeq': ackedSeq,
        'protocolVersion': protocolVersion,
        if (revokedAt != null) 'revokedAt': revokedAt,
        'createdAt': createdAt,
      };

  @override
  String toString() => 'Peer($id, $name, ${kind.wire}, revoked=$isRevoked)';
}
