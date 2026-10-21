import 'dart:async';

import '../models/enums.dart';
import '../models/item.dart';

/// Secure-storage abstraction for the phone's device token (`PAIR-004`).
///
/// Android implements this with Keystore-backed storage; the desktop never
/// stores tokens (it stores only hashes in SQLite). A file fallback must use
/// 0600 permissions and is only for tests/headless Linux.
abstract class TokenStore {
  Future<String?> read(String ref);
  Future<void> write(String ref, String value);
  Future<void> delete(String ref);
}

/// In-memory implementation for tests and `tool/fake_peer.dart`.
class MemoryTokenStore implements TokenStore {
  final Map<String, String> _tokens = <String, String>{};

  @override
  Future<String?> read(String ref) async => _tokens[ref];

  @override
  Future<void> write(String ref, String value) async => _tokens[ref] = value;

  @override
  Future<void> delete(String ref) async => _tokens.remove(ref);
}

/// Stable secure-storage key per peer.
String peerTokenRef(String peerId) => 'peer.$peerId.token';

/// Android `MulticastLock` wrapper (held only while discovering).
abstract class MulticastLock {
  Future<void> acquire();
  Future<void> release();
}

class NoopMulticastLock implements MulticastLock {
  @override
  Future<void> acquire() async {}

  @override
  Future<void> release() async {}
}

/// Platform notifications for the non-UI (keep-alive) engine and the UI.
///
/// The core never formats message content into a log; [onIncomingItem] receives
/// the item so the platform can show a first-80-characters notification.
abstract class CoreNotifier {
  Future<void> onIncomingItem(Item item);
  Future<void> onConnectionChanged(ConnectionStatus status);
  Future<void> clear();
}

class NoopNotifier implements CoreNotifier {
  @override
  Future<void> onIncomingItem(Item item) async {}

  @override
  Future<void> onConnectionChanged(ConnectionStatus status) async {}

  @override
  Future<void> clear() async {}
}

/// Where the core runs: the desktop hosts, the phone dials (`docs/03`).
enum CorePlatform { desktop, phone }
