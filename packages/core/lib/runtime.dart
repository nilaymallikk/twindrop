import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'db/database.dart';
import 'db/store_ops.dart';
import 'models/enums.dart';
import 'models/errors.dart';
import 'models/item.dart';
import 'models/peer.dart';
import 'protocol/pairing_payload.dart';
import 'net/connection_manager.dart';
import 'net/discovery.dart';
import 'net/host_server.dart';
import 'net/pairing_client.dart';
import 'services/chat_service.dart';
import 'services/export_service.dart';
import 'services/notepad_service.dart';
import 'services/pairing_service.dart';
import 'services/peer_registry.dart';
import 'services/quarantine_service.dart';
import 'services/service_base.dart';
import 'services/settings_store.dart';
import 'services/share_ingest.dart';
import 'services/stores.dart';
import 'sync/change_bus.dart';
import 'sync/merge_engine.dart';
import 'sync/sync_engine.dart';
import 'tls/tls_identity.dart';
import 'util/hlc.dart';
import 'util/ids.dart';
import 'util/logger.dart';

class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    required this.platform,
    required this.deviceId,
    required this.deviceName,
    required this.localAddresses,
    required this.serverRunning,
    required this.port,
    required this.mdnsRunning,
    required this.peers,
    required this.connectedPeerIds,
    required this.queuedItems,
    required this.quarantineCount,
    required this.status,
    required this.fingerprint,
    required this.lastError,
  });

  final CorePlatform platform;
  final String deviceId;
  final String deviceName;
  final List<String> localAddresses;
  final bool serverRunning;
  final int port;
  final bool mdnsRunning;
  final List<Peer> peers;
  final Set<String> connectedPeerIds;
  final int queuedItems;
  final int quarantineCount;
  final ConnectionStatus status;
  final String? fingerprint;
  final String? lastError;
}

/// The single facade the Flutter app (and the Android headless engine) talks
/// to. All state lives in the local replica; all services are shared.
class CoreRuntime {
  CoreRuntime._({
    required this.platform,
    required this.db,
    required this.deviceId,
    required this.deviceName,
    required this.dataDir,
    required this.localAddresses,
    required this.settings,
    required this.clock,
    required this.bus,
    required this.peers,
    required this.sync,
    required this.chat,
    required this.notepad,
    required this.exportService,
    required this.shareIngest,
    required this.quarantine,
    required this.logger,
    required this.tokenStore,
    required this.notifier,
    required this.pairingClient,
    this.identity,
    this.host,
    this.connection,
    this.mdns,
    this.discovery,
    this.appVersion = '0.1.0',
  });

  final CorePlatform platform;
  final AppDatabase db;
  final String deviceId;
  final String deviceName;
  final String dataDir;
  final SettingsStore settings;
  final HlcClock clock;
  final ChangeBus bus;
  final PeerRegistry peers;
  final SyncEngine sync;
  final ChatService chat;
  final NotepadService notepad;
  final ExportService exportService;
  final ShareIngest shareIngest;
  final QuarantineService quarantine;
  final Logger logger;

  /// Phone only; the desktop stores token hashes in SQLite.
  final TokenStore tokenStore;
  final CoreNotifier notifier;
  final PairingClient pairingClient;
  final TlsIdentity? identity;
  final HostServer? host;
  final ConnectionManager? connection;
  final MdnsAnnouncer? mdns;
  final MdnsDiscovery? discovery;
  final String appVersion;

  PairingService? get pairingService => host?.pairing;

  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<Map<String, ConnectionStatus>> _peerStatesController =
      StreamController<Map<String, ConnectionStatus>>.broadcast();

  ConnectionStatus _status = ConnectionStatus.unpaired;
  Timer? _hostIdleTimer;
  StreamSubscription<ConnectionStatus>? _connStatusSub;
  StreamSubscription<Set<String>>? _hostSessionsSub;
  final List<String> localAddresses;
  StreamSubscription<int>? _busSub;
  int _lastNotifiedCreatedAt = 0;
  String? _lastError;
  bool _started = false;
  bool _paused = false;

  ConnectionStatus get status => _status;
  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  Stream<Map<String, ConnectionStatus>> get peerStatesStream =>
      _peerStatesController.stream;
  Stream<int> get revisionStream => bus.stream;
  Stream<List<Peer>> get peersStream => peers.watch();
  String? get lastError => _lastError;

  /// Open the replica and wire every service. Never performs network I/O.
  static Future<CoreRuntime> open({
    required CorePlatform platform,
    required String deviceName,
    required String dataDir,
    TokenStore? tokenStore,
    MulticastLock? multicastLock,
    CoreNotifier? notifier,
    List<String> sanIps = const <String>[],
    int preferredPort = 47321,
    bool enableDiscovery = true,
    bool inMemory = false,
    Logger? logger,
    String? deviceId,
    String appVersion = '0.1.0',
  }) async {
    final log = logger ?? Logger.silent;
    final db = inMemory ? AppDatabase.memory() : _openDatabase(dataDir, log);
    final settings = SettingsStore(db);
    final cleanLinks = _CleanLinksFlag();
    cleanLinks.value = await settings.cleanLinks();

    var id = deviceId ?? await settings.getString(SettingsKeys.deviceId);
    if (id == null || id.isEmpty) {
      id = newId();
      await settings.setString(SettingsKeys.deviceId, id);
    }
    await settings.setString(SettingsKeys.deviceName, deviceName);
    await settings.setString(SettingsKeys.deviceKind, platform.name);

    final clock = HlcClock(
      deviceId: id,
      last: Hlc.tryParse(await db.lastHlcValue()),
    );
    final bus = ChangeBus();
    final peers = PeerRegistry(db: db, bus: bus, logger: log);
    final merge = MergeEngine(db: db, clock: clock, logger: log);
    final sync = SyncEngine(
      db: db,
      merge: merge,
      clock: clock,
      bus: bus,
      logger: log,
    );
    final tokens = tokenStore ?? MemoryTokenStore();
    final notepad = NotepadService(
      db: db,
      clock: clock,
      bus: bus,
      logger: log,
      deviceId: id,
      deviceName: deviceName,
      cleanLinks: () => cleanLinks.value,
    );
    final chat = ChatService(
      db: db,
      clock: clock,
      bus: bus,
      logger: log,
      peers: peers,
      deviceId: id,
      deviceName: deviceName,
      cleanLinks: () => cleanLinks.value,
    );
    final shareIngest = ShareIngest(
      db: db,
      clock: clock,
      bus: bus,
      logger: log,
      notepad: notepad,
      chat: chat,
      settings: settings,
    );
    final exportService = ExportService(
      db: db,
      notepad: notepad,
      deviceName: deviceName,
    );
    final quarantine = QuarantineService(db: db, logger: log);
    await notepad.ensureInbox();

    final localIps = sanIps.isNotEmpty ? sanIps : await _localAddresses();
    TlsIdentity? identity;
    HostServer? host;
    MdnsAnnouncer? mdns;
    if (platform == CorePlatform.desktop) {
      final tlsDir = Directory('$dataDir/tls');
      identity = await TlsIdentity.loadOrCreate(
        tlsDir,
        sanIps: sanIps.isNotEmpty ? sanIps : localIps,
        logger: log,
      );
      host = HostServer(
        identity: identity,
        db: db,
        sync: sync,
        bus: bus,
        peers: peers,
        logger: log,
        deviceId: id,
        deviceName: deviceName,
        appVersion: appVersion,
        versionName: () => appVersion,
        localHosts: () => localIps,
        preferredPort: preferredPort,
      );
      if (enableDiscovery) {
        mdns = MdnsAnnouncer(
          deviceId: id,
          deviceName: deviceName,
          fingerprint: identity.fingerprint,
          port: preferredPort,
          interfaceAddresses: () => localIps,
          logger: log,
        );
      }
    }

    ConnectionManager? connection;
    MdnsDiscovery? discovery;
    if (platform == CorePlatform.phone) {
      discovery = enableDiscovery
          ? MdnsDiscovery(logger: log, multicastLock: multicastLock)
          : null;
      connection = ConnectionManager(
        db: db,
        sync: sync,
        bus: bus,
        peers: peers,
        tokenStore: tokens,
        logger: log,
        deviceId: id,
        deviceName: deviceName,
        deviceKind: PeerKind.phone,
        appVersion: appVersion,
        discovery: discovery,
        multicastLock: multicastLock,
        notifier: notifier,
      );
    }

    final runtime = CoreRuntime._(
      platform: platform,
      db: db,
      deviceId: id,
      deviceName: deviceName,
      dataDir: dataDir,
      localAddresses: localIps,
      settings: settings,
      clock: clock,
      bus: bus,
      peers: peers,
      sync: sync,
      chat: chat,
      notepad: notepad,
      exportService: exportService,
      shareIngest: shareIngest,
      quarantine: quarantine,
      logger: log,
      tokenStore: tokens,
      notifier: notifier ?? NoopNotifier(),
      pairingClient: PairingClient(logger: log),
      identity: identity,
      host: host,
      connection: connection,
      mdns: mdns,
      discovery: discovery,
      appVersion: appVersion,
    );
    return runtime;
  }

  static AppDatabase _openDatabase(String dataDir, Logger logger) {
    final dir = Directory(dataDir)..createSync(recursive: true);
    final file = File('$dataDir/twindrop.db');
    final db = AppDatabase.openAt(file.path);
    // Integrity is checked lazily by the caller because the check is async.
    logger.debug('db: opened', fields: {'dir': dir.path});
    return db;
  }

  static Future<List<String>> _localAddresses() async {
    final out = <String>[];
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final address in iface.addresses) {
          if (address.isLoopback) continue;
          final a = address.address;
          if (a.startsWith('169.254.')) continue;
          out.add(a);
        }
      }
    } on Object {
      // Fall through to loopback, used by tests and single-machine runs.
    }
    if (out.isEmpty) out.add('127.0.0.1');
    return out;
  }

  /// Start networking according to the platform and the paused flag.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _paused = await settings.paused();
    if (platform == CorePlatform.desktop) {
      _hostSessionsSub = host!.sessions.listen(_onHostSessions);
      final active = await peers.active();
      if (active.isNotEmpty && !_paused) {
        await _ensureHost();
      } else if (active.isEmpty) {
        _setStatus(ConnectionStatus.unpaired);
      } else {
        _setStatus(ConnectionStatus.paused);
      }
    } else {
      _lastNotifiedCreatedAt = DateTime.now().millisecondsSinceEpoch;
      _connStatusSub = connection!.statusStream.listen(_setStatus);
      connection!.retryNow();
      await connection!.start();
      _busSub = bus.stream.listen((_) => _notifyIncoming());
      _setStatus(connection!.status);
    }
  }

  Future<void> _ensureHost() async {
    final h = host;
    if (h == null) return;
    if (!h.isRunning) {
      final port = await h.start();
      mdns?.port = port;
      final running = await mdns?.start() ?? false;
      logger.info('runtime: host up', fields: {'port': port, 'mdns': running});
    }
    if (mdns != null && !mdns!.isRunning) await mdns!.start();
  }

  void _onHostSessions(Set<String> sessions) {
    _peerStatesController.add(<String, ConnectionStatus>{
      for (final id in sessions) id: ConnectionStatus.connected,
    });
    _setStatus(sessions.isNotEmpty
        ? ConnectionStatus.connected
        : (_paused ? ConnectionStatus.paused : ConnectionStatus.searching));
  }

  void _setStatus(ConnectionStatus status) {
    if (_status == status) return;
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
    if (platform == CorePlatform.phone) {
      unawaited(notifier.onConnectionChanged(status));
    }
  }

  Future<void> _notifyIncoming() async {
    if (platform != CorePlatform.phone) return;
    final messages = await chat.listMessages(limit: 20);
    for (final item in messages) {
      if (item.originDevice == deviceId) continue;
      if (item.createdAt <= _lastNotifiedCreatedAt) continue;
      _lastNotifiedCreatedAt = item.createdAt;
      await notifier.onIncomingItem(item);
    }
  }

  // ---------------------------------------------------------------- desktop ---

  /// Open a pairing window and start the host long enough to receive the phone.
  Future<PairingSession> startPairingSession({bool manual = false}) async {
    if (platform != CorePlatform.desktop) {
      throw const ForbiddenError('pairing host runs on the desktop');
    }
    await _ensureHost();
    final session = host!.pairing.startSession(manual: manual);
    _hostIdleTimer?.cancel();
    _hostIdleTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      host!.pairing.prune();
      if (!host!.pairing.isOpen &&
          (await peers.active()).isEmpty &&
          host!.connectedPeerIds.isEmpty) {
        await _stopHostIdle();
      }
    });
    _setStatus(ConnectionStatus.pairing);
    return session;
  }

  Future<void> cancelPairingSession() async {
    host?.pairing.cancelSession();
    if ((await peers.active()).isEmpty) await _stopHostIdle();
  }

  Future<Peer> approvePairing(String requestId) async {
    final peer = await host!.pairing.approve(requestId);
    await _ensureHost();
    return peer;
  }

  Future<void> rejectPairing(String requestId) =>
      host!.pairing.reject(requestId);

  /// Revoke a device (desktop) — closes its live socket with 4403.
  Future<void> revokePeer(String peerId) async {
    await peers.revoke(peerId);
    if ((await peers.active()).isEmpty && host?.pairing.isOpen != true) {
      await _stopHostIdle();
    }
  }

  Future<void> _stopHostIdle() async {
    _hostIdleTimer?.cancel();
    _hostIdleTimer = null;
    await mdns?.stop();
    await host?.stop();
    if (!_statusController.isClosed) _setStatus(ConnectionStatus.unpaired);
  }

  // ------------------------------------------------------------------ phone ---

  Future<String> probeManual(String host, int port) async {
    final probe = await pairingClient.probeManual(host, port);
    return probe.shortFingerprint;
  }

  Future<ManualProbe> manualProbe(String host, int port) =>
      pairingClient.probeManual(host, port);

  Future<PairedDesktop> pairWithQr({
    required String payload,
    required void Function(String code) onCode,
    void Function(String desktopName)? onWait,
  }) async {
    final parsed = PairingPayload.parse(payload);
    final result = await pairingClient.pairWithPayload(
      payload: parsed,
      clientDeviceId: deviceId,
      displayName: deviceName,
      platform: 'android',
      onCode: onCode,
      onWait: onWait,
    );
    await _storePairedDesktop(result);
    return result;
  }

  Future<PairedDesktop> pairManually({
    required ManualProbe probe,
    required String code,
    required void Function(String code) onCode,
  }) async {
    final result = await pairingClient.pairManually(
      probe: probe,
      code: code,
      clientDeviceId: deviceId,
      displayName: deviceName,
      platform: 'android',
      onCode: onCode,
    );
    await _storePairedDesktop(result);
    return result;
  }

  Future<void> _storePairedDesktop(PairedDesktop result) async {
    await tokenStore.write(
      peerTokenRef(result.hostDeviceId),
      result.deviceToken,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await peers.addPairedPeer(Peer(
      id: result.hostDeviceId,
      name: result.hostName,
      kind: PeerKind.desktop,
      roleOfPeer: PeerRole.host,
      tokenRef: peerTokenRef(result.hostDeviceId),
      certFp: result.fingerprint,
      lastHost: result.host,
      lastPort: result.port,
      lastSeen: now,
      protocolVersion: result.protocolVersion,
      createdAt: now,
    ));
    connection?.setManualAddress(result.host, result.port);
    _setStatus(ConnectionStatus.searching);
    await connection?.start();
  }

  Future<void> unpair() async {
    await connection?.unpair();
    _setStatus(ConnectionStatus.unpaired);
  }

  Future<void> pause() async {
    _paused = true;
    await settings.setPaused(true);
    if (platform == CorePlatform.desktop) {
      await mdns?.stop();
      await host?.stop();
      _setStatus(ConnectionStatus.paused);
    } else {
      await connection?.pause();
    }
  }

  Future<void> resume() async {
    _paused = false;
    await settings.setPaused(false);
    if (platform == CorePlatform.desktop) {
      if ((await peers.active()).isNotEmpty) {
        await _ensureHost();
        _setStatus(ConnectionStatus.searching);
      } else {
        _setStatus(ConnectionStatus.unpaired);
      }
    } else {
      await connection?.resume();
    }
  }

  void retryNow() => connection?.retryNow();

  /// Phone UI owns the connection while it is foreground; the keep-alive
  /// service owns it while the UI is backgrounded.
  Future<void> startConnection() async => connection?.start();

  Future<void> stopConnection() => connection?.stop() ?? Future<void>.value();

  Future<ShareResult> importNativeShare({
    required String shareId,
    required String text,
    String? sourceApp,
    ShareDefaultAction? action,
  }) async {
    final key = 'share.imported.$shareId';
    final already = await settings.getBool(key);
    if (already) {
      throw const ValidationError('share already imported');
    }
    final result = await shareIngest.ingestText(
      text: text,
      sourceApp: sourceApp,
      action: action,
    );
    await settings.setBool(key, true);
    return result;
  }

  Future<DiagnosticsSnapshot> diagnostics() async {
    final peerList = await peers.list();
    final queued = await db.queuedDeliveryCount();
    final q = await quarantine.count();
    final connected = platform == CorePlatform.desktop
        ? (host?.connectedPeerIds ?? const <String>{})
        : (connection?.connectedPeerIds ?? const <String>{});
    return DiagnosticsSnapshot(
      platform: platform,
      deviceId: deviceId,
      deviceName: deviceName,
      localAddresses: localAddresses,
      serverRunning: host?.isRunning ?? false,
      port: host?.port ?? 0,
      mdnsRunning: mdns?.isRunning ?? false,
      peers: peerList,
      connectedPeerIds: connected,
      queuedItems: queued,
      quarantineCount: q,
      status: status,
      fingerprint: identity?.fingerprint,
      lastError: _lastError,
    );
  }

  Future<void> stop({bool pause = false}) async {
    if (pause) this.pauseOnStop = true;
    await mdns?.stop();
    await host?.stop();
    await connection?.stop();
    await discovery?.dispose();
    await _connStatusSub?.cancel();
    await _hostSessionsSub?.cancel();
    await _busSub?.cancel();
    _hostIdleTimer?.cancel();
  }

  bool pauseOnStop = false;

  Future<void> dispose() async {
    await stop(pause: pauseOnStop);
    await peers.dispose();
    await bus.dispose();
    await _statusController.close();
    await _peerStatesController.close();
    await mdns?.stop();
    await host?.dispose();
    await discovery?.dispose();
    await db.close();
  }
}

class _CleanLinksFlag {
  bool value = true;
}
