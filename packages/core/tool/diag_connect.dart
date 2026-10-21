// Temporary diagnostic for the two-peer connection stall.
import 'dart:async';
import 'dart:io';

import 'package:twindrop_core/core.dart';

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp('twindrop-diag-');
  final deskDir = Directory('${root.path}/desk')..createSync();
  final phoneDir = Directory('${root.path}/phone')..createSync();
  final log = Logger(level: LogLevel.debug);

  final desk = await CoreRuntime.open(
    platform: CorePlatform.desktop,
    deviceName: 'Desk',
    dataDir: deskDir.path,
    sanIps: const ['127.0.0.1'],
    inMemory: true,
    logger: log,
    enableDiscovery: false,
  );
  final phone = await CoreRuntime.open(
    platform: CorePlatform.phone,
    deviceName: 'Phone',
    dataDir: phoneDir.path,
    inMemory: true,
    logger: log,
    enableDiscovery: false,
  );

  phone.connection!.statusStream.listen((s) => print('PHONE STATUS -> ${s.wire}'));

  await desk.start();
  await phone.start();

  final session = await desk.startPairingSession();
  print('payload host=${session.payload.hosts} port=${session.payload.port}');

  final approved = Completer<void>();
  String? deskCode;
  final sub = desk.pairingService!.requests.listen((request) async {
    if (request.state != PairingState.pendingApproval) return;
    deskCode = request.confirmationCode;
    print('DESK request code=$deskCode');
    await desk.approvePairing(request.requestId);
    if (!approved.isCompleted) approved.complete();
  });

  String? phoneCode;
  final paired = phone.pairWithQr(
    payload: session.payload.encode(),
    onCode: (code) {
      phoneCode = code;
      print('PHONE code=$code');
    },
  );
  final result = await paired.timeout(const Duration(seconds: 20));
  await approved.future.timeout(const Duration(seconds: 10));
  print('PAIRED host=${result.host}:${result.port} fp=${result.fingerprint} '
      'phoneCode=$phoneCode');

  final active = await phone.peers.active();
  print('PHONE active peers=${active.length}');
  for (final p in active) {
    print('  peer id=${p.id} name=${p.name} host=${p.lastHost} port=${p.lastPort} '
        'fp=${p.certFp} tokenRef=${p.tokenRef} revoked=${p.isRevoked}');
  }
  final token = await phone.tokenStore.read('peer.${result.hostDeviceId}');
  print('PHONE token present=${token != null}');
  print('PHONE tokenRef candidates: peerTokenRef(host)=${result.hostDeviceId}');
  print('PHONE conn status=${phone.connection!.status.wire}');
  print('PHONE diagnostics connected=${(await phone.diagnostics()).connectedPeerIds}');

  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(const Duration(seconds: 1));
    final d = await desk.diagnostics();
    final p = await phone.diagnostics();
    print('t=${i + 1}s deskConn=${d.connectedPeerIds} phoneConn=${p.connectedPeerIds} '
        'phoneStatus=${phone.connection!.status.wire}');
    if (d.connectedPeerIds.isNotEmpty && p.connectedPeerIds.isNotEmpty) {
      print('CONNECTED');
      break;
    }
  }

  await sub.cancel();
  await phone.dispose();
  await desk.dispose();
  await root.delete(recursive: true);
}
