import 'dart:math';

import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';

import 'support/test_support.dart';

void main() {
  late AppDatabase db;
  late ChangeBus bus;
  late PeerRegistry peers;
  late SyncEngine sync;
  late HlcClock clock;
  late MergeEngine merge;
  late ConnectionManager manager;

  setUp(() {
    db = AppDatabase.memory();
    bus = ChangeBus();
    clock = HlcClock(deviceId: 'phone', nowMs: () => 1000);
    merge = MergeEngine(db: db, clock: clock, logger: Logger.silent);
    sync = SyncEngine(
      db: db,
      merge: merge,
      clock: clock,
      bus: bus,
      logger: Logger.silent,
    );
    peers = PeerRegistry(db: db, bus: bus, logger: Logger.silent);
  });

  tearDown(() async {
    await manager.dispose();
    await db.close();
    await bus.dispose();
  });

  ConnectionManager buildManager() => ConnectionManager(
        db: db,
        sync: sync,
        bus: bus,
        peers: peers,
        tokenStore: MemoryTokenStore(),
        logger: Logger.silent,
        deviceId: 'phone-device',
        deviceName: 'Phone',
        deviceKind: PeerKind.phone,
        appVersion: '0.1.0',
        // A seeded random keeps the jitter deterministic.
        random: Random(42),
      );

  group('backoff', () {
    test('starts at one second', () {
      manager = buildManager();
      expect(manager.backoffSeconds, 1);
    });

    test('stays inside the documented 1..30 second window', () async {
      manager = buildManager();
      await manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(manager.backoffSeconds, greaterThanOrEqualTo(1));
      expect(manager.backoffSeconds, lessThanOrEqualTo(30));
      await manager.stop();
    });

    test('retryNow resets the backoff to the first step', () async {
      manager = buildManager();
      await manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      manager.retryNow();
      expect(manager.backoffSeconds, 1);
      await manager.stop();
    });

    test('does not hammer the network when no peer is paired', () async {
      manager = buildManager();
      final events = <ConnectionStatus>[];
      final sub = manager.statusStream.listen(events.add);
      addTearDown(sub.cancel);

      await manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(
        events,
        isEmpty,
        reason: 'the manager must not spin while it has nothing to do',
      );
      expect(manager.status, ConnectionStatus.unpaired);
      await manager.stop();
    });
  });

  group('lifecycle', () {
    test('reports "unpaired" when no peer is known', () async {
      manager = buildManager();
      final events = <ConnectionStatus>[];
      final sub = manager.statusStream.listen(events.add);
      addTearDown(sub.cancel);

      await manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(manager.status, ConnectionStatus.unpaired);
      expect(
        events.where((e) => e != ConnectionStatus.unpaired),
        isEmpty,
        reason: 'without a paired peer there is nothing else to report',
      );
      await manager.stop();
    });

    test('pause and resume flip the status', () async {
      manager = buildManager();
      await manager.start();
      await manager.pause();
      expect(manager.isPaused, isTrue);
      expect(manager.status, ConnectionStatus.paused);
      await manager.resume();
      expect(manager.isPaused, isFalse);
      await manager.stop();
    });

    test('a manual address can be configured', () {
      manager = buildManager();
      manager.setManualAddress('127.0.0.1', 47321);
      expect(manager, isNotNull);
    });

    test('a peer without a token is never dialled', () async {
      await peers.addPairedPeer(makePeer(id: 'desktop-1')); // no token ref
      manager = buildManager();
      final events = <ConnectionStatus>[];
      final sub = manager.statusStream.listen(events.add);
      addTearDown(sub.cancel);

      await manager.start();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(manager.status, ConnectionStatus.unpaired);
      expect(events, isNot(contains(ConnectionStatus.connecting)));
      await manager.stop();
    });
  });
}
