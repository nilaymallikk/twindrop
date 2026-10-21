import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';

void main() {
  group('FrameCodec', () {
    test('round-trips a hello frame', () {
      final frame = HelloFrame(
        deviceId: 'device-1',
        name: 'Phone',
        kind: PeerKind.phone,
        appVersion: '0.1.0',
      );
      final decoded = FrameCodec.decode(FrameCodec.encode(frame));
      expect(decoded, isA<HelloFrame>());
      final hello = decoded as HelloFrame;
      expect(hello.deviceId, 'device-1');
      expect(hello.name, 'Phone');
      expect(hello.kind, PeerKind.phone);
      expect(hello.v, FrameCodec.protocolVersion);
    });

    test('round-trips a ready frame', () {
      final frame = ReadyFrame(
        deviceId: 'desktop-1',
        name: 'Desktop',
        seq: 42,
        serverTime: 1000,
      );
      final decoded = FrameCodec.decode(FrameCodec.encode(frame)) as ReadyFrame;
      expect(decoded.seq, 42);
      expect(decoded.deviceId, 'desktop-1');
    });

    test('round-trips a pull frame', () {
      final decoded =
          FrameCodec.decode(FrameCodec.encode(PullFrame(after: 7, limit: 50)))
              as PullFrame;
      expect(decoded.after, 7);
      expect(decoded.limit, 50);
    });

    test('round-trips a changes frame', () {
      final page = ChangePage(
        records: [
          ChangeRecord(seq: 1, entityType: 'item', entityId: 'a'),
        ],
        next: 1,
        more: false,
      );
      final decoded =
          FrameCodec.decode(FrameCodec.encode(ChangesFrame(page))) as ChangesFrame;
      expect(decoded.page.records.length, 1);
      expect(decoded.page.records.first.entityId, 'a');
      expect(decoded.page.next, 1);
    });

    test('round-trips a notify, ack, ping and pong frame', () {
      expect(
        (FrameCodec.decode(FrameCodec.encode(NotifyFrame(seq: 3))) as NotifyFrame)
            .seq,
        3,
      );
      expect(
        (FrameCodec.decode(FrameCodec.encode(AckFrame(seq: 9))) as AckFrame).seq,
        9,
      );
      expect(
        (FrameCodec.decode(FrameCodec.encode(PingFrame(ts: 5))) as PingFrame).ts,
        5,
      );
      expect(
        (FrameCodec.decode(FrameCodec.encode(PongFrame(ts: 6))) as PongFrame).ts,
        6,
      );
    });

    test('an unknown frame type is ignored, not fatal', () {
      final decoded = FrameCodec.decode('{"t":"future","x":1}');
      expect(decoded, isA<UnknownFrame>());
      expect((decoded as UnknownFrame).type, 'future');
    });

    test('malformed JSON is a protocol error', () {
      expect(() => FrameCodec.decode('not json'), throwsA(isA<ProtocolError>()));
      expect(() => FrameCodec.decode('[1,2]'), throwsA(isA<ProtocolError>()));
      expect(() => FrameCodec.decode('{}'), throwsA(isA<ProtocolError>()));
      expect(
        () => FrameCodec.decode('{"t":""}'),
        throwsA(isA<ProtocolError>()),
      );
    });

    test('a frame from a newer protocol stops the sync', () {
      final raw = '{"t":"hello","v":99,"id":"a","name":"b","kind":"phone",'
          '"app":"1.0"}';
      expect(
        () => FrameCodec.decode(raw),
        throwsA(isA<UnsupportedVersionError>()),
      );
    });

    test('an oversize frame is rejected, never truncated', () {
      final big = '{"t":"ping","ts":${'9' * (FrameCodec.maxFrameBytes + 10)}}';
      expect(
        () => FrameCodec.decode(big),
        throwsA(isA<PayloadTooLargeError>()),
      );
      expect(
        () => FrameCodec.encode(PingFrame(ts: 1)),
        returnsNormally,
      );
    });

    test('an oversize outgoing frame is rejected', () {
      // A frame whose JSON exceeds 1 MiB must fail to encode.
      final huge = 'x' * (FrameCodec.maxFrameBytes + 100);
      expect(
        () => FrameCodec.encode(ErrorFrame(code: 'x', message: huge)),
        throwsA(isA<PayloadTooLargeError>()),
      );
    });
  });

  group('ChangePage', () {
    test('round-trips through JSON', () {
      final page = ChangePage(
        records: [
          ChangeRecord(
            seq: 4,
            entityType: 'item',
            entityId: 'abc',
            row: <String, dynamic>{'text': 'hi'},
          ),
        ],
        next: 4,
        more: true,
      );
      final decoded = ChangePage.fromJson(page.toJson());
      expect(decoded.records.length, 1);
      expect(decoded.records.first.seq, 4);
      expect(decoded.records.first.row!['text'], 'hi');
      expect(decoded.more, isTrue);
    });

    test('rejects a malformed page', () {
      expect(
        () => ChangePage.fromJson(<String, dynamic>{'entries': 'x'}),
        throwsA(isA<ProtocolError>()),
      );
      expect(
        () => ChangePage.fromJson(<String, dynamic>{
          'entries': <dynamic>[],
          'next': 'x',
          'more': false,
        }),
        throwsA(isA<ProtocolError>()),
      );
      expect(
        () => ChangePage.fromJson(<String, dynamic>{
          'entries': <dynamic>['not a map'],
          'next': 1,
          'more': false,
        }),
        throwsA(isA<ProtocolError>()),
      );
    });
  });
}
