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
export 'util/logger.dart';
export 'util/ids.dart';
export 'validators/validators.dart';

export 'models/errors.dart';
export 'net/connection_manager.dart';
export 'net/discovery.dart';
export 'net/host_server.dart';
export 'net/pairing_client.dart';
export 'net/peer_session.dart';
export 'protocol/close_codes.dart';
export 'protocol/frames.dart';
export 'protocol/pairing_guard.dart';
export 'protocol/pairing_payload.dart';
export 'runtime.dart';
export 'services/chat_service.dart';
export 'services/export_service.dart';
export 'services/item_builder.dart';
export 'services/notepad_service.dart';
export 'services/pairing_service.dart';
export 'services/peer_registry.dart';
export 'services/quarantine_service.dart';
export 'services/service_base.dart';
export 'services/settings_store.dart';
export 'services/share_ingest.dart';
export 'services/stores.dart';
export 'sync/change_bus.dart';
export 'sync/merge_engine.dart';
export 'sync/remote_validation.dart';
export 'sync/sync_engine.dart';
export 'tls/tls_identity.dart';
