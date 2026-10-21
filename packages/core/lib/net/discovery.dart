import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:multicast_dns/multicast_dns.dart';

import '../services/stores.dart';
import '../util/logger.dart';

/// Result of an mDNS browse (`docs/05` §Discovery).
class DiscoveredHost {
  const DiscoveredHost({
    required this.host,
    required this.port,
    required this.deviceId,
    required this.deviceName,
    required this.fingerprintHint,
  });

  final String host;
  final int port;
  final String deviceId;
  final String deviceName;

  /// First 8 hex of the pin: a hint only, never authority.
  final String fingerprintHint;
}

/// Phone-side mDNS browse for `_twindrop._tcp.local`.
///
/// The multicast lock is acquired by the caller (ConnectionManager) because it
/// must be held only while a lookup is in flight.
class MdnsDiscovery {
  MdnsDiscovery({Logger? logger, MulticastLock? multicastLock})
    : _logger = logger,
      _multicastLock = multicastLock;

  final Logger? _logger;
  final MulticastLock? _multicastLock;
  MDnsClient? _client;

  static const String serviceType = '_twindrop._tcp.local';

  Future<MDnsClient> _ensureClient() async {
    final existing = _client;
    if (existing != null) return existing;
    final client = MDnsClient();
    await client.start(
      onError: (Object e) {
        _logger?.debug('mdns: socket error', fields: {'error': e.runtimeType});
      },
    );
    _client = client;
    return client;
  }

  /// Find the first advertised host; optionally require the 8-hex pin hint to
  /// match so another TwinDrop instance on the LAN is ignored.
  Future<DiscoveredHost?> find({
    String? expectedPin,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    await _multicastLock?.acquire();
    try {
      final client = await _ensureClient();
      final ptr = await client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(serviceType),
          )
          .first
          .timeout(timeout);
      final srv = await client
          .lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
          )
          .first
          .timeout(timeout);
      final txtRecords = await client
          .lookup<TxtResourceRecord>(ResourceRecordQuery.text(ptr.domainName))
          .toList()
          .timeout(timeout);
      final txt = <String, String>{};
      for (final record in txtRecords) {
        final idx = record.text.indexOf('=');
        if (idx <= 0) continue;
        txt[record.text.substring(0, idx)] = record.text.substring(idx + 1);
      }
      final hint = txt['fp8'] ?? '';
      if (expectedPin != null &&
          expectedPin.isNotEmpty &&
          hint.isNotEmpty &&
          !expectedPin.toLowerCase().startsWith(hint.toLowerCase())) {
        _logger?.warn('mdns: pin hint mismatch, ignoring host');
        return null;
      }
      if (txt['v'] != null && txt['v'] != '1') {
        _logger?.warn('mdns: unsupported service version');
        return null;
      }
      final address = await client
          .lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )
          .first
          .timeout(timeout);
      return DiscoveredHost(
        host: address.address.address,
        port: srv.port,
        deviceId: txt['id'] ?? '',
        deviceName: txt['name'] ?? '',
        fingerprintHint: hint,
      );
    } on TimeoutException {
      return null;
    } on Object catch (e) {
      _logger?.debug('mdns: lookup failed', fields: {'error': e.runtimeType});
      return null;
    } finally {
      await _multicastLock?.release();
    }
  }

  Future<void> dispose() async {
    _client?.stop();
    _client = null;
  }
}

/// Desktop-side mDNS announcer for `_twindrop._tcp.local`.
///
/// `multicast_dns` can only browse, so responses are encoded by hand. The
/// announcement carries only `v`, `id`, `name`, `fp8` — never a token or
/// content (`docs/08` §mDNS).
class MdnsAnnouncer {
  MdnsAnnouncer({
    required this.deviceId,
    required this.deviceName,
    required this.fingerprint,
    required this.port,
    required this.interfaceAddresses,
    Logger? logger,
  }) : _logger = logger,
       _hostName =
           'twindrop-${deviceId.replaceAll('-', '').substring(0, 8)}'
           '.local';

  final String deviceId;
  final String deviceName;
  final String fingerprint;
  int port;
  final String _hostName;

  /// Current non-loopback IPv4 addresses (the A records to publish).
  final List<String> Function() interfaceAddresses;
  final Logger? _logger;

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _announceTimer;
  bool _running = false;

  static final InternetAddress _group = InternetAddress('224.0.0.251');
  static const int _mdnsPort = 5353;
  static const String _service = '_twindrop._tcp.local';

  String get instanceName => '$deviceName.$_service';
  String get hostName => _hostName;

  bool get isRunning => _running;

  Future<bool> start() async {
    if (_running) return true;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _mdnsPort,
        reuseAddress: true,
        reusePort: true,
        ttl: 255,
      );
      socket.multicastLoopback = true;
      _joinInterfaces(socket);
      _socket = socket;
      _running = true;
      _subscription = socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          final datagram = socket.receive();
          if (datagram == null) return;
          _maybeRespond(socket, datagram.data, datagram.address, datagram.port);
        },
        onError: (Object e) {
          _logger?.debug(
            'mdns: announcer socket error',
            fields: {'error': e.runtimeType},
          );
        },
      );
      announce();
      _announceTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        announce();
      });
      _logger?.info('mdns: announcing', fields: {'host': _hostName});
      return true;
    } on Object catch (e) {
      _logger?.warn(
        'mdns: announce unavailable',
        fields: {'error': e.runtimeType},
      );
      _running = false;
      return false;
    }
  }

  void _joinInterfaces(RawDatagramSocket socket) {
    NetworkInterface.list(type: InternetAddressType.IPv4)
        .then((list) {
          for (final iface in list) {
            try {
              socket.joinMulticast(_group, iface);
            } on Object {
              // Interface may not support multicast (e.g. some VPNs).
            }
          }
        })
        .catchError((Object _) {
          try {
            socket.joinMulticast(_group);
          } on Object {
            // Multicast unavailable: the app still works via last IP/manual.
          }
        });
  }

  void announce() {
    final socket = _socket;
    if (socket == null || !_running) return;
    try {
      socket.send(_responsePacket(0), _group, _mdnsPort);
    } on Object {
      // best effort
    }
  }

  void _maybeRespond(
    RawDatagramSocket socket,
    Uint8List data,
    InternetAddress from,
    int fromPort,
  ) {
    if (data.length < 12) return;
    try {
      final flags = (data[2] << 8) | data[3];
      if ((flags & 0x8000) != 0) return; // a response, not a query
      final id = (data[0] << 8) | data[1];
      final qdCount = (data[4] << 8) | data[5];
      var offset = 12;
      var interesting = false;
      for (var i = 0; i < qdCount; i++) {
        final read = _readName(data, offset);
        if (read == null) return;
        offset = read.next;
        if (offset + 4 > data.length) return;
        final type = (data[offset] << 8) | data[offset + 1];
        offset += 4;
        final name = read.name.toLowerCase();
        if (name == _service ||
            name == instanceName.toLowerCase() ||
            name == hostName.toLowerCase() ||
            (type == 12 && name == _service)) {
          interesting = true;
        }
      }
      if (!interesting) return;
      socket.send(_responsePacket(id), from, fromPort);
    } on Object {
      // Malformed query: ignore.
    }
  }

  Uint8List _responsePacket(int id) {
    final addresses = interfaceAddresses()
        .map((a) => InternetAddress.tryParse(a))
        .whereType<InternetAddress>()
        .where((a) => a.type == InternetAddressType.IPv4)
        .toList();
    if (addresses.isEmpty) addresses.add(InternetAddress.loopbackIPv4);
    final writer = _Writer();
    writer.u16(id);
    writer.u16(0x8400); // response, authoritative
    writer.u16(0); // questions
    writer.u16(4 + addresses.length - 1); // answers
    writer.u16(0);
    writer.u16(0);

    // PTR
    writer.recordName(_service, type: 12, ttl: 120, rdataName: instanceName);
    // SRV
    final srv = _Writer();
    srv.u16(0);
    srv.u16(0);
    srv.u16(port);
    srv.name(hostName);
    writer.record(instanceName, 33, 120, srv);
    // TXT
    final txt = _Writer();
    for (final value in <String>[
      'v=1',
      'id=$deviceId',
      'name=${_sanitizeTxt(deviceName)}',
      'fp8=${fingerprint.length >= 8 ? fingerprint.substring(0, 8) : fingerprint}',
    ]) {
      final bytes = utf8.encode(value);
      txt.u8(bytes.length.clamp(0, 255));
      txt.raw(bytes.take(255).toList());
    }
    writer.record(instanceName, 16, 120, txt);
    // A records (one per live interface)
    for (final address in addresses) {
      writer.record(hostName, 1, 120, _Writer()..raw(address.rawAddress));
    }
    return writer.bytes;
  }

  static String _sanitizeTxt(String value) =>
      value.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();

  Future<void> stop() async {
    _running = false;
    _announceTimer?.cancel();
    _announceTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _socket?.close();
    _socket = null;
  }
}

class _NameRead {
  const _NameRead(this.name, this.next);
  final String name;
  final int next;
}

_NameRead? _readName(Uint8List data, int start) {
  final labels = <String>[];
  var offset = start;
  var jumped = false;
  var guard = 0;
  while (offset < data.length && guard++ < 128) {
    final length = data[offset];
    if (length == 0) {
      offset += 1;
      return _NameRead(labels.join('.'), jumped ? start + 2 : offset);
    }
    if ((length & 0xc0) == 0xc0) {
      if (offset + 1 >= data.length) return null;
      final pointer = ((length & 0x3f) << 8) | data[offset + 1];
      if (pointer >= data.length) return null;
      if (!jumped) {
        final next = offset + 2;
        final inner = _readName(data, pointer);
        if (inner == null) return null;
        if (inner.name.isNotEmpty) labels.add(inner.name);
        return _NameRead(labels.join('.'), next);
      }
      return null;
    }
    if (offset + 1 + length > data.length) return null;
    labels.add(
      utf8.decode(
        data.sublist(offset + 1, offset + 1 + length),
        allowMalformed: true,
      ),
    );
    offset += 1 + length;
  }
  return null;
}

class _Writer {
  final BytesBuilder _builder = BytesBuilder();

  void u8(int value) => _builder.addByte(value & 0xff);

  void u16(int value) {
    _builder.addByte((value >> 8) & 0xff);
    _builder.addByte(value & 0xff);
  }

  void u32(int value) {
    _builder.addByte((value >> 24) & 0xff);
    _builder.addByte((value >> 16) & 0xff);
    _builder.addByte((value >> 8) & 0xff);
    _builder.addByte(value & 0xff);
  }

  void raw(List<int> bytes) => _builder.add(bytes);

  void name(String value) {
    for (final label in value.split('.')) {
      if (label.isEmpty) continue;
      final bytes = utf8.encode(label);
      u8(bytes.length);
      raw(bytes);
    }
    u8(0);
  }

  void record(
    String nameValue,
    int type,
    int ttl,
    _Writer rdata, {
    bool cacheFlush = true,
  }) {
    name(nameValue);
    u16(type);
    u16(cacheFlush ? 0x8001 : 1);
    u32(ttl);
    final bytes = rdata.bytes;
    u16(bytes.length);
    raw(bytes);
  }

  void recordName(
    String nameValue, {
    required int type,
    required int ttl,
    required String rdataName,
  }) {
    final rdata = _Writer()..name(rdataName);
    record(nameValue, type, ttl, rdata, cacheFlush: false);
  }

  Uint8List get bytes => _builder.toBytes();
}
