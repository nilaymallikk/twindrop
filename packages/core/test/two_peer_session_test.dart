import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';
import 'package:twindrop_core/db/store_ops.dart';

/// Wait until [condition] is true or the deadline expires.
Future<bool> waitUntil(
  Future<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  Duration step = const Duration(milliseconds: 50),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await condition()) return true;
    await Future<void>.delayed(step);
  }
  return await condition();
}

/// True when the replica already holds the message with [id].
Future<bool> _hasMessage(AppDatabase db, String id) async {
  final items = await db.listItems(type: ItemType.message, limit: 100);
  return items.any((m) => m.id == id);
}

void main() {
  const phoneId = '018f0000-0000-7000-8000-0000000000ph';
  const desktopId = '018f0000-0000-7000-8000-0000000000de';
  const token = 'cGFpcnVkLWRldmljZS10b2tlbi12YWx1ZS0xMjM0NTY3ODkw';

  late AppDatabase desktopDb;
  late AppDatabase phoneDb;
  late ChangeBus desktopBus;
  late ChangeBus phoneBus;
  late PeerRegistry desktopPeers;
  late PeerRegistry phonePeers;
  late HlcClock desktopClock;
  late HlcClock phoneClock;
  late MergeEngine desktopMerge;
  late MergeEngine phoneMerge;
  late SyncEngine desktopSync;
  late SyncEngine phoneSync;
  late ChatService desktopChat;
  late ChatService phoneChat;
  late NotepadService desktopNotepad;
  late NotepadService phoneNotepad;
  late HostServer host;
  late ConnectionManager connection;
  late MemoryTokenStore tokenStore;

  setUp(() async {
    desktopDb = AppDatabase.memory();
    phoneDb = AppDatabase.memory();
    desktopBus = ChangeBus();
    phoneBus = ChangeBus();
    desktopClock = HlcClock(deviceId: desktopId, nowMs: () => 1000);
    phoneClock = HlcClock(deviceId: phoneId, nowMs: () => 1000);
    desktopMerge = MergeEngine(
      db: desktopDb,
      clock: desktopClock,
      logger: Logger.silent,
    );
    phoneMerge = MergeEngine(
      db: phoneDb,
      clock: phoneClock,
      logger: Logger.silent,
    );
    desktopSync = SyncEngine(
      db: desktopDb,
      merge: desktopMerge,
      clock: desktopClock,
      bus: desktopBus,
      logger: Logger.silent,
    );
    phoneSync = SyncEngine(
      db: phoneDb,
      merge: phoneMerge,
      clock: phoneClock,
      bus: phoneBus,
      logger: Logger.silent,
    );
    desktopPeers = PeerRegistry(
      db: desktopDb,
      bus: desktopBus,
      logger: Logger.silent,
    );
    phonePeers = PeerRegistry(
      db: phoneDb,
      bus: phoneBus,
      logger: Logger.silent,
    );
    desktopChat = ChatService(
      db: desktopDb,
      clock: desktopClock,
      bus: desktopBus,
      logger: Logger.silent,
      peers: desktopPeers,
      deviceId: desktopId,
      deviceName: 'Desktop',
      nowMs: () => 1000,
    );
    phoneChat = ChatService(
      db: phoneDb,
      clock: phoneClock,
      bus: phoneBus,
      logger: Logger.silent,
      peers: phonePeers,
      deviceId: phoneId,
      deviceName: 'Phone',
      nowMs: () => 1000,
    );
    desktopNotepad = NotepadService(
      db: desktopDb,
      clock: desktopClock,
      bus: desktopBus,
      logger: Logger.silent,
      deviceId: desktopId,
      deviceName: 'Desktop',
      nowMs: () => 1000,
    );
    phoneNotepad = NotepadService(
      db: phoneDb,
      clock: phoneClock,
      bus: phoneBus,
      logger: Logger.silent,
      deviceId: phoneId,
      deviceName: 'Phone',
      nowMs: () => 1000,
    );
    await desktopNotepad.ensureInbox();
    await phoneNotepad.ensureInbox();

    final identity = await TlsIdentity.loadOrCreate(
      await Directory.systemTemp.createTemp('twindrop_twopeer_'),
      sanIps: const ['127.0.0.1'],
    );
    host = HostServer(
      identity: identity,
      db: desktopDb,
      sync: desktopSync,
      bus: desktopBus,
      peers: desktopPeers,
      logger: Logger.silent,
      deviceId: desktopId,
      deviceName: 'Desktop',
      appVersion: '0.1.0',
      versionName: () => '0.1.0',
      localHosts: () => const ['127.0.0.1'],
      preferredPort: 0,
    );
    await host.start();

    // The desktop knows the phone (and stores only the token hash).
    await desktopPeers.addPairedPeer(Peer(
      id: phoneId,
      name: 'Phone',
      kind: PeerKind.phone,
      roleOfPeer: PeerRole.guest,
      tokenHash: DeviceTokens.hash(token),
      createdAt: 1000,
    ));

    // The phone knows the desktop and holds the pin.
    await phonePeers.addPairedPeer(Peer(
      id: desktopId,
      name: 'Desktop',
      kind: PeerKind.desktop,
      roleOfPeer: PeerRole.host,
      tokenRef: peerTokenRef(desktopId),
      certFp: identity.fingerprint,
      lastHost: '127.0.0.1',
      lastPort: host.port,
      createdAt: 1000,
    ));
    tokenStore = MemoryTokenStore();
    await tokenStore.write(peerTokenRef(desktopId), token);

    connection = ConnectionManager(
      db: phoneDb,
      sync: phoneSync,
      bus: phoneBus,
      peers: phonePeers,
      tokenStore: tokenStore,
      logger: Logger.silent,
      deviceId: phoneId,
      deviceName: 'Phone',
      deviceKind: PeerKind.phone,
      appVersion: '0.1.0',
    );
  });

  tearDown(() async {
    await connection.dispose();
    await host.dispose();
    await desktopDb.close();
    await phoneDb.close();
    await desktopBus.dispose();
    await phoneBus.dispose();
  });

  group('two peers over loopback TLS', () {
    test('the phone connects and the session becomes ready', () async {
      await connection.start();
      final connected = await waitUntil(
        () async => connection.status == ConnectionStatus.connected,
        timeout: const Duration(seconds: 20),
      );
      expect(connected, isTrue,
          reason: 'the phone never reached the connected state');
      expect(host.connectedPeerIds, contains(phoneId));
    });

    test('a message from the desktop arrives on the phone exactly once',
        () async {
      await connection.start();
      expect(
        await waitUntil(
          () async => connection.status == ConnectionStatus.connected,
          timeout: const Duration(seconds: 20),
        ),
        isTrue,
      );

      final message = await desktopChat.sendMessage('hello from the desktop');
      final delivered =
          await waitUntil(() => _hasMessage(phoneDb, message.id));
      expect(delivered, isTrue, reason: 'the message never arrived');

      final messages = await phoneChat.listMessages();
      expect(messages.length, 1);
      expect(messages.first.text, 'hello from the desktop');
      expect(messages.first.originDevice, desktopId);
    });

    test('a message from the phone arrives on the desktop', () async {
      await connection.start();
      expect(
        await waitUntil(
          () async => connection.status == ConnectionStatus.connected,
          timeout: const Duration(seconds: 20),
        ),
        isTrue,
      );

      final message = await phoneChat.sendMessage('hello from the phone');
      final delivered = await waitUntil(
        () => _hasMessage(desktopDb, message.id),
      );
      expect(delivered, isTrue, reason: 'the message never arrived');

      final messages = await desktopChat.listMessages();
      expect(messages.length, 1);
      expect(messages.first.text, 'hello from the phone');
    });

    test('both cursors advance independently and never overshoot', () async {
      await connection.start();
      expect(
        await waitUntil(
          () async => connection.status == ConnectionStatus.connected,
          timeout: const Duration(seconds: 20),
        ),
        isTrue,
      );

      final message = await desktopChat.sendMessage('cursor check');
      expect(await waitUntil(() => _hasMessage(phoneDb, message.id)), isTrue);

      // The phone applied the desktop's change log.
      final phonePeer = await phoneDb.peerById(desktopId);
      expect(phonePeer!.remoteSeq, greaterThan(0));
      // The desktop applied the phone's change log (the Inbox category).
      final desktopPeer = await desktopDb.peerById(phoneId);
      expect(desktopPeer!.remoteSeq, greaterThan(0));

      // A cursor can never point past the peer's latest change.
      final desktopSeq = await desktopDb.lastChangeSeq();
      expect(phonePeer.remoteSeq, lessThanOrEqualTo(desktopSeq));
    });

    test('the same message is not delivered twice', () async {
      await connection.start();
      expect(
        await waitUntil(
          () async => connection.status == ConnectionStatus.connected,
          timeout: const Duration(seconds: 20),
        ),
        isTrue,
      );

      final message = await desktopChat.sendMessage('exactly once');
      expect(await waitUntil(() => _hasMessage(phoneDb, message.id)), isTrue);

      // Give the sync a chance to run again.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final messages = await phoneChat.listMessages();
      expect(messages.length, 1);
      expect(messages.where((m) => m.id == message.id).length, 1);
    });
  });
}
