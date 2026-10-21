import 'dart:convert';

import '../models/enums.dart';
import '../models/errors.dart';
import '../sync/change_bus.dart' show ChangeBus;
import '../sync/sync_engine.dart';

/// WS frame codec (`docs/05` §Session).
///
/// All frames are JSON text objects with a `t` type discriminator. Unknown
/// types decode to [UnknownFrame] and are ignored (forward compatibility);
/// malformed frames and oversize payloads are rejected, never truncated.
sealed class Frame {
  const Frame();
  String get type;
  Map<String, dynamic> toJson();
}

class HelloFrame extends Frame {
  const HelloFrame({
    this.v = FrameCodec.protocolVersion,
    required this.deviceId,
    required this.name,
    required this.kind,
    required this.appVersion,
  });

  final int v;
  final String deviceId;
  final String name;
  final PeerKind kind;
  final String appVersion;

  @override
  String get type => 'hello';

  @override
  Map<String, dynamic> toJson() => {
    't': type,
    'v': v,
    'id': deviceId,
    'name': name,
    'kind': kind.wire,
    'app': appVersion,
  };
}

class ReadyFrame extends Frame {
  const ReadyFrame({
    this.v = FrameCodec.protocolVersion,
    required this.deviceId,
    required this.name,
    required this.seq,
    required this.serverTime,
  });

  final int v;
  final String deviceId;
  final String name;

  /// Highest change-log seq the host currently has.
  final int seq;
  final int serverTime;

  @override
  String get type => 'ready';

  @override
  Map<String, dynamic> toJson() => {
    't': type,
    'v': v,
    'id': deviceId,
    'name': name,
    'seq': seq,
    'serverTime': serverTime,
  };
}

class PullFrame extends Frame {
  const PullFrame({required this.after, this.limit = 200});

  final int after;
  final int limit;

  @override
  String get type => 'pull';

  @override
  Map<String, dynamic> toJson() => {'t': type, 'after': after, 'limit': limit};
}

class ChangesFrame extends Frame {
  const ChangesFrame(this.page);
  final ChangePage page;

  @override
  String get type => 'changes';

  @override
  Map<String, dynamic> toJson() => {'t': type, ...page.toJson()};
}

class NotifyFrame extends Frame {
  const NotifyFrame({required this.seq, this.inline});

  /// Highest local change-log seq after a commit.
  final int seq;

  /// Optional inline changes (<= 20 rows) to save a round trip.
  final ChangePage? inline;

  @override
  String get type => 'notify';

  @override
  Map<String, dynamic> toJson() => {
    't': type,
    'seq': seq,
    if (inline != null) 'inline': inline!.toJson(),
  };
}

class AckFrame extends Frame {
  const AckFrame({required this.seq});

  /// Highest peer page seq applied locally (`docs/05`).
  final int seq;

  @override
  String get type => 'ack';

  @override
  Map<String, dynamic> toJson() => {'t': type, 'seq': seq};
}

class PingFrame extends Frame {
  const PingFrame({required this.ts});
  final int ts;

  @override
  String get type => 'ping';

  @override
  Map<String, dynamic> toJson() => {'t': type, 'ts': ts};
}

class PongFrame extends Frame {
  const PongFrame({required this.ts});
  final int ts;

  @override
  String get type => 'pong';

  @override
  Map<String, dynamic> toJson() => {'t': type, 'ts': ts};
}

class ErrorFrame extends Frame {
  const ErrorFrame({
    required this.code,
    required this.message,
    this.retryable = false,
  });

  final String code;
  final String message;
  final bool retryable;

  @override
  String get type => 'error';

  @override
  Map<String, dynamic> toJson() => {
    't': type,
    'code': code,
    'message': message,
    'retryable': retryable,
  };
}

/// A frame type this version does not know: ignored, never fatal
/// (`docs/05`: unknown message types are forward compatible).
class UnknownFrame extends Frame {
  const UnknownFrame(this.type, this.json);
  @override
  final String type;
  final Map<String, dynamic> json;

  @override
  Map<String, dynamic> toJson() => json;
}

/// Encode/decode WS frames.
abstract final class FrameCodec {
  static const int protocolVersion = 1;

  /// 1 MiB hard limit (`docs/08` §Input handling).
  static const int maxFrameBytes = 1024 * 1024;

  /// Upper bound on change entries per frame.
  static const int maxEntriesPerFrame = 1000;

  static String encode(Frame frame) {
    final json = jsonEncode(frame.toJson());
    if (utf8.encode(json).length > maxFrameBytes) {
      throw const PayloadTooLargeError('outgoing frame too large');
    }
    return json;
  }

  /// Decode a frame. Throws [ProtocolError] for malformed data,
  /// [PayloadTooLargeError] over the frame limit and [UnsupportedVersionError]
  /// for an unknown protocol version (which must stop sync, not be skipped).
  static Frame decode(String raw) {
    if (utf8.encode(raw).length > maxFrameBytes) {
      throw const PayloadTooLargeError('frame too large');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const ProtocolError('frame is not JSON');
    }
    if (decoded is! Map) throw const ProtocolError('frame is not an object');
    final json = Map<String, dynamic>.from(decoded);
    final t = json['t'];
    if (t is! String || t.isEmpty || t.length > 32) {
      throw const ProtocolError('missing frame type');
    }
    switch (t) {
      case 'hello':
        return _hello(json);
      case 'ready':
        return _ready(json);
      case 'pull':
        return PullFrame(
          after: _int(json, 'after'),
          limit: _int(json, 'limit'),
        );
      case 'changes':
        return ChangesFrame(ChangePage.fromJson(json));
      case 'notify':
        final inline = json['inline'];
        return NotifyFrame(
          seq: _int(json, 'seq'),
          inline: inline == null
              ? null
              : ChangePage.fromJson(_map(inline, 'inline')),
        );
      case 'ack':
        return AckFrame(seq: _int(json, 'seq'));
      case 'ping':
        return PingFrame(ts: _int(json, 'ts'));
      case 'pong':
        return PongFrame(ts: _int(json, 'ts'));
      case 'error':
        return ErrorFrame(
          code: _string(json, 'code', maxLength: 64),
          message: _string(json, 'message', maxLength: 500),
          retryable: json['retryable'] == true,
        );
      default:
        return UnknownFrame(t, json);
    }
  }

  static Frame _hello(Map<String, dynamic> json) {
    final v = _int(json, 'v');
    if (v > protocolVersion) {
      throw const UnsupportedVersionError(
        'peer uses a newer protocol version; update TwinDrop',
      );
    }
    if (v != protocolVersion) throw const ProtocolError('bad version');
    return HelloFrame(
      v: v,
      deviceId: _string(json, 'id', maxLength: 100),
      name: _string(json, 'name', maxLength: 100),
      kind: _kind(json['kind']),
      appVersion: _string(json, 'app', maxLength: 40),
    );
  }

  static Frame _ready(Map<String, dynamic> json) {
    final v = _int(json, 'v');
    if (v > protocolVersion) {
      throw const UnsupportedVersionError(
        'peer uses a newer protocol version; update TwinDrop',
      );
    }
    if (v != protocolVersion) throw const ProtocolError('bad version');
    return ReadyFrame(
      v: v,
      deviceId: _string(json, 'id', maxLength: 100),
      name: _string(json, 'name', maxLength: 100),
      seq: _int(json, 'seq'),
      serverTime: _int(json, 'serverTime'),
    );
  }

  static PeerKind _kind(Object? raw) {
    if (raw is! String) throw const ProtocolError('invalid peer kind');
    try {
      return PeerKind.parse(raw);
    } on FormatException {
      throw const ProtocolError('invalid peer kind');
    }
  }

  static int _int(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v is! int) throw ProtocolError('missing/invalid $key');
    return v;
  }

  static String _string(
    Map<String, dynamic> json,
    String key, {
    required int maxLength,
  }) {
    final v = json[key];
    if (v is! String || v.length > maxLength) {
      throw ProtocolError('missing/invalid $key');
    }
    return v;
  }

  static Map<String, dynamic> _map(Object raw, String key) {
    if (raw is! Map) throw ProtocolError('invalid $key');
    return Map<String, dynamic>.from(raw);
  }
}

/// Error frame from a typed failure (`docs/05` error format).
ErrorFrame errorFrameFor(TwinDropError error) => ErrorFrame(
  code: error.code,
  message: error.message,
  retryable: error.retryable,
);

/// Convenience for session code: highest seq currently committed.
Future<int> latestSeq(ChangeBus bus, int Function() read) async => read();
