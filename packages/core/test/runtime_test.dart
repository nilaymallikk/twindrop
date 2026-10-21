import 'dart:io';

import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';
import 'package:twindrop_core/db/store_ops.dart';

void main() {
  late Directory dataDir;

  setUp(() async {
    dataDir = await Directory.systemTemp.createTemp('twindrop_runtime_test_');
  });

  tearDown(() async {
    if (dataDir.existsSync()) await dataDir.delete(recursive: true);
  });

  group('CoreRuntime.open (desktop)', () {
    test('wires every service without touching the network', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.desktop,
        deviceName: 'Desktop',
        deviceId: '018f0000-0000-7000-8000-00000000desk',
        dataDir: dataDir.path,
        sanIps: const ['127.0.0.1'],
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);

      expect(runtime.platform, CorePlatform.desktop);
      expect(runtime.deviceName, 'Desktop');
      expect(runtime.deviceId, '018f0000-0000-7000-8000-00000000desk');
      expect(runtime.status, ConnectionStatus.unpaired);
      expect(runtime.identity, isNotNull);
      expect(runtime.identity!.fingerprint.length, 64);
      expect(runtime.mdns, isNull, reason: 'discovery is disabled');
      expect(runtime.host, isNotNull);
      expect(runtime.host!.isRunning, isFalse);
      expect(runtime.connection, isNull);
    });

    test('creates the Inbox and stores notes and messages', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.desktop,
        deviceName: 'Desktop',
        dataDir: dataDir.path,
        sanIps: const ['127.0.0.1'],
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);

      final inbox = await runtime.db.categoryById(Category.inboxId);
      expect(inbox, isNotNull);
      expect(inbox!.isInbox, isTrue);

      final note = await runtime.notepad.createNote(text: 'a note');
      expect(note.categoryId, Category.inboxId);
      final message = await runtime.chat.sendMessage('hello');
      expect(message.isMessage, isTrue);
      expect((await runtime.chat.listMessages()).length, 1);
    });

    test('the device id and the HLC are persisted', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.desktop,
        deviceName: 'Desktop',
        dataDir: dataDir.path,
        sanIps: const ['127.0.0.1'],
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);

      await runtime.notepad.createNote(text: 'a note');
      final hlc = await runtime.db.lastHlcValue();
      expect(hlc, isNotNull);
      expect(Hlc.tryParse(hlc), isNotNull);
    });

    test('diagnostics reports the local state', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.desktop,
        deviceName: 'Desktop',
        dataDir: dataDir.path,
        sanIps: const ['127.0.0.1'],
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);

      final snapshot = await runtime.diagnostics();
      expect(snapshot.platform, CorePlatform.desktop);
      expect(snapshot.deviceName, 'Desktop');
      expect(snapshot.serverRunning, isFalse);
      expect(snapshot.peers, isEmpty);
      expect(snapshot.quarantineCount, 0);
      expect(snapshot.fingerprint, runtime.identity!.fingerprint);
      expect(snapshot.status, ConnectionStatus.unpaired);
    });

    test('start does not open a server while no peer is paired', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.desktop,
        deviceName: 'Desktop',
        dataDir: dataDir.path,
        sanIps: const ['127.0.0.1'],
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);

      await runtime.start();
      expect(
        runtime.host!.isRunning,
        isFalse,
        reason: 'SEC-007: no server without a paired peer',
      );
      expect(runtime.status, ConnectionStatus.unpaired);
    });

    test('pause and resume toggle the paused state', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.desktop,
        deviceName: 'Desktop',
        dataDir: dataDir.path,
        sanIps: const ['127.0.0.1'],
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);

      await runtime.pause();
      expect(await runtime.settings.paused(), isTrue);
      expect(runtime.status, ConnectionStatus.paused);
      await runtime.resume();
      expect(await runtime.settings.paused(), isFalse);
      expect(runtime.status, ConnectionStatus.unpaired);
    });

    test('a revoked peer disappears from the active list', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.desktop,
        deviceName: 'Desktop',
        dataDir: dataDir.path,
        sanIps: const ['127.0.0.1'],
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);

      await runtime.peers.addPairedPeer(
        Peer(
          id: 'phone-1',
          name: 'Phone',
          kind: PeerKind.phone,
          roleOfPeer: PeerRole.guest,
          createdAt: 1000,
        ),
      );
      expect((await runtime.peers.active()).length, 1);
      await runtime.revokePeer('phone-1');
      expect((await runtime.peers.active()).length, 0);
      final peer = await runtime.peers.get('phone-1');
      expect(peer!.isRevoked, isTrue);
    });

    test('a share is imported exactly once per share id', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.desktop,
        deviceName: 'Desktop',
        dataDir: dataDir.path,
        sanIps: const ['127.0.0.1'],
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);

      final first = await runtime.importNativeShare(
        shareId: 'share-1',
        text: 'https://example.com/page',
        sourceApp: 'com.android.chrome',
      );
      expect(first.item, isNotNull);
      expect(first.item!.categoryId, Category.inboxId);

      await expectLater(
        runtime.importNativeShare(
          shareId: 'share-1',
          text: 'https://example.com/page',
        ),
        throwsA(isA<ValidationError>()),
        reason: 'the same Android share must not create two notes',
      );
      final notes = await runtime.notepad.listNotes(
        categoryId: Category.inboxId,
      );
      expect(notes.length, 1);
    });
  });

  group('CoreRuntime.open (phone)', () {
    test('wires the connection manager without discovery', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.phone,
        deviceName: 'Phone',
        dataDir: dataDir.path,
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);

      expect(runtime.platform, CorePlatform.phone);
      expect(runtime.connection, isNotNull);
      expect(runtime.discovery, isNull);
      expect(
        runtime.identity,
        isNull,
        reason: 'the phone never owns a TLS identity',
      );
      expect(runtime.host, isNull);
      expect(runtime.tokenStore, isA<MemoryTokenStore>());
    });

    test('reports "unpaired" while no desktop is known', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.phone,
        deviceName: 'Phone',
        dataDir: dataDir.path,
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);

      await runtime.start();
      expect(runtime.status, ConnectionStatus.unpaired);
      await runtime.stopConnection();
    });

    test('pause and resume are recorded in the settings', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.phone,
        deviceName: 'Phone',
        dataDir: dataDir.path,
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);

      await runtime.start();
      await runtime.pause();
      expect(await runtime.settings.paused(), isTrue);
      expect(runtime.status, ConnectionStatus.paused);
      await runtime.resume();
      expect(await runtime.settings.paused(), isFalse);
      await runtime.stopConnection();
    });
  });

  group('settings store', () {
    test('stores and reads typed values', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.desktop,
        deviceName: 'Desktop',
        dataDir: dataDir.path,
        sanIps: const ['127.0.0.1'],
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);
      final settings = runtime.settings;

      await settings.setString('a.b', 'value');
      expect(await settings.getString('a.b'), 'value');
      await settings.remove('a.b');
      expect(await settings.getString('a.b'), isNull);

      await settings.setBool('a.flag', true);
      expect(await settings.getBool('a.flag'), isTrue);
      expect(await settings.getBool('a.missing'), isFalse);
      expect(await settings.getBool('a.missing', fallback: true), isTrue);

      await settings.setInt('a.number', 42);
      expect(await settings.getInt('a.number'), 42);
      expect(await settings.getInt('a.missing'), isNull);
    });

    test('uses the documented defaults', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.desktop,
        deviceName: 'Desktop',
        dataDir: dataDir.path,
        sanIps: const ['127.0.0.1'],
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);
      final settings = runtime.settings;

      expect(await settings.theme(), AppThemeChoice.dark);
      await settings.setTheme(AppThemeChoice.light);
      expect(await settings.theme(), AppThemeChoice.light);

      expect(await settings.cleanLinks(), isTrue);
      await settings.setCleanLinks(false);
      expect(await settings.cleanLinks(), isFalse);

      expect(await settings.notificationsEnabled(), isTrue);
      expect(await settings.keepAliveConsent(), isTrue);
      await settings.setKeepAliveConsent(false);
      expect(await settings.keepAliveConsent(), isFalse);
      expect(await settings.shareDefaultAction(), ShareDefaultAction.notepad);
      await settings.setShareDefaultAction(ShareDefaultAction.chat);
      expect(await settings.shareDefaultAction(), ShareDefaultAction.chat);
    });
  });

  group('quarantine service', () {
    test('lists, counts and clears the quarantine', () async {
      final runtime = await CoreRuntime.open(
        platform: CorePlatform.desktop,
        deviceName: 'Desktop',
        dataDir: dataDir.path,
        sanIps: const ['127.0.0.1'],
        enableDiscovery: false,
        inMemory: true,
        logger: Logger.silent,
      );
      addTearDown(runtime.dispose);

      expect(await runtime.quarantine.count(), 0);
      expect(await runtime.quarantine.list(), isEmpty);

      await runtime.db.quarantine(
        QuarantineEntry(
          id: 0,
          peerId: 'peer-b',
          entityType: 'item',
          entityId: 'item-1',
          reason: QuarantineReason.invalidUrl.wire,
          payloadJson: '{}',
          receivedAt: 1000,
        ),
      );
      expect(await runtime.quarantine.count(), 1);
      expect((await runtime.quarantine.list()).first.entityId, 'item-1');

      await runtime.quarantine.clear();
      expect(await runtime.quarantine.count(), 0);
    });
  });
}
