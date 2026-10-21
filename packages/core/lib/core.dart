/// TwinDrop core — pure Dart (no Flutter imports).
///
/// Data, sync, protocol, TLS identity/pinning, pairing, validators and export
/// live here so the exact same logic runs on Android and Linux.
library;

export 'db/database.dart';
export 'db/mappers.dart';
export 'models/category.dart';
export 'models/change.dart';
export 'models/enums.dart';
export 'models/item.dart';
export 'models/peer.dart';
export 'util/hashing.dart';
export 'util/hlc.dart';
export 'util/ids.dart';
export 'validators/validators.dart';

// Service, protocol, TLS and networking layers are exported here as they land:
// export 'services/...';
// export 'protocol/...';
// export 'tls/...';
// export 'net/...';
