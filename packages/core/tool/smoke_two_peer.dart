// Integration smoke: two in-process runtimes, real pinned TLS over loopback,
// pairing, then chat both ways. Run: dart run tool/smoke_two_peer.dart
import 'dart:async';
import 'dart:io';

import 'package:twindrop_core/core.dart';

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('twindrop-smoke-');
  final deskDir = Directory('${root.path}/desk')..createSync();
  final phoneDir = Directory('${root.path}/phone')..createSync();
  final log = Logger(level: LogLevel.info);

  final desk = await CoreRuntime.open(
    platform: CorePlatform.desktop,
    deviceName: 'Desk',
    dataDir: deskDir.path,
    sanIps: const ['127.0.0.1'],
    inMemory: true,
    logger: log,
    enableDiscovery: false,
    preferredPort: 47321,
  );
  final phone = await CoreRuntime.open(
    platform: CorePlatform.phone,
    deviceName: 'Phone',
    dataDir: phoneDir.path,
    inMemory: true,
    logger: log,
    enableDiscovery: false,
  );
  await desk.start();
  await phone.start();

  final session = await desk.startPairingSession();
  print('session port=${session.payload.port} hosts=${session.payload.hosts}');

  String? phoneCode;
  String? requestId;
  String? deskCode;
  final approved = Completer<void>();
  final sub = desk.pairingService!.requests.listen((request) async {
    if (requestId != null) return;
    if (request.state != PairingState.pendingApproval) return;
    requestId = request.requestId;
    deskCode = request.confirmationCode;
    print('request ${request.displayName} code=$deskCode phone=$phoneCode');
    await desk.approvePairing(request.requestId);
    if (!approved.isCompleted) approved.complete();
  });

  final paired = phone.pairWithQr(
    payload: session.payload.encode(),
    onCode: (code) {
      phoneCode = code;
      print('phone code=$code');
    },
  );

  final result = await paired.timeout(const Duration(seconds: 30));
  await approved.future.timeout(const Duration(seconds: 10));
  print('paired host=${result.hostName} id=${result.hostDeviceId}');
  if (deskCode == null || phoneCode == null || deskCode != phoneCode) {
    throw StateError('confirmation codes differ: $deskCode vs $phoneCode');
  }

  await _waitFor(
    () async {
      final d = await desk.diagnostics();
      final p = await phone.diagnostics();
      print(
        'status desk=${d.status} phone=${p.status} connected desk=${d.connectedPeerIds} phone=${p.connectedPeerIds}',
      );
      return p.connectedPeerIds.isNotEmpty && d.connectedPeerIds.isNotEmpty;
    },
    const Duration(seconds: 20),
    'both connected',
  );
  print('connected on both sides');

  await phone.chat.sendMessage('hello from phone');
  final deskMsg = await _waitFor(
    () async {
      final msgs = await desk.chat.listMessages();
      final found = msgs.where((m) => m.text == 'hello from phone').toList();
      return found.isNotEmpty ? found.first : null;
    },
    const Duration(seconds: 10),
    'desk receives',
  );
  print('desktop received ${deskMsg.id}');

  await desk.chat.sendMessage('hello from desktop');
  final phoneMsg = await _waitFor(
    () async {
      final msgs = await phone.chat.listMessages();
      final found = msgs.where((m) => m.text == 'hello from desktop').toList();
      return found.isNotEmpty ? found.first : null;
    },
    const Duration(seconds: 10),
    'phone receives',
  );
  print('phone received ${phoneMsg.id}');

  final delivered = await _waitFor(
    () async {
      final info = await desk.chat.deliveryFor(phoneMsg.id);
      return info.isNotEmpty &&
          info.every((i) => i.state == DeliveryState.delivered);
    },
    const Duration(seconds: 10),
    'delivered',
  );
  print('delivery states ok=$delivered');

  final phoneMessages = await phone.chat.listMessages();
  final deskMessages = await desk.chat.listMessages();
  print(
    'phone messages=${phoneMessages.length} desk messages=${deskMessages.length}',
  );
  if (phoneMessages.where((m) => m.text == 'hello from desktop').length != 1) {
    throw StateError('duplicate desktop message on phone');
  }
  if (deskMessages.where((m) => m.text == 'hello from phone').length != 1) {
    throw StateError('duplicate phone message on desktop');
  }

  await sub.cancel();
  await phone.dispose();
  await desk.dispose();
  await root.delete(recursive: true);
  print('SMOKE_OK');
}

Future<T> _waitFor<T>(
  Future<T?> Function() probe,
  Duration timeout,
  String label,
) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final value = await probe();
    if (value != null && value != false) return value;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException(label);
}
