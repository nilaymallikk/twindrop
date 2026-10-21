import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';

import 'support/test_support.dart';

void main() {
  group('Hlc value format', () {
    test('encodes a fixed-width wall time and counter', () {
      final h = Hlc(1234567890123, 42, 'dev-a');
      expect(h.value, '001234567890123-00042-dev-a');
      // Wall is 15 digits, counter is 5 digits, device id is free-form.
      final parts = h.value.split('-');
      expect(parts[0].length, 15);
      expect(parts[1].length, 5);
      expect(h.value.endsWith('-dev-a'), isTrue);
    });

    test('parse round-trips a value', () {
      final h = Hlc(1700000000000, 7, 'dev-b');
      final parsed = Hlc.parse(h.value);
      expect(parsed.wallMs, 1700000000000);
      expect(parsed.counter, 7);
      expect(parsed.deviceId, 'dev-b');
      expect(parsed, h);
      expect(parsed.hashCode, h.hashCode);
    });

    test('parse throws FormatException for malformed values', () {
      for (final bad in <String>[
        '',
        'not-a-hlc',
        '123',
        '123456789012345', // no counter/device
        '123456789012345-00001', // no device id
        '123456789012345-00001-', // empty device id
        '12345678901234-00001-dev', // wall too short
        '1234567890123456-00001-dev', // wall too long
        '123456789012345-0001-dev', // counter too short
        '123456789012345-000001-dev', // counter too long
        '123456789012345-0000a-dev', // non-numeric counter
      ]) {
        expect(() => Hlc.parse(bad), throwsFormatException,
            reason: 'should reject "$bad"');
      }
    });

    test('parse keeps the device id verbatim', () {
      // The device id is free-form (it is a UUID in production, but the
      // encoder/decoder must not silently mangle it).
      final parsed = Hlc.parse('123456789012345-00001-dev extra');
      expect(parsed.deviceId, 'dev extra');
    });

    test('tryParse returns null instead of throwing', () {
      expect(Hlc.tryParse('not-a-hlc'), isNull);
      expect(Hlc.tryParse(''), isNull);
      expect(Hlc.tryParse(null), isNull);
      expect(Hlc.tryParse('123456789012345-00001-dev'),
          isNotNull);
    });
  });

  group('Hlc ordering', () {
    test('orders by wall time first', () {
      final older = Hlc(1000, 99999, 'z');
      final newer = Hlc(1001, 0, 'a');
      expect(newer.compareTo(older), greaterThan(0));
      expect(newer > older, isTrue);
      expect(older < newer, isTrue);
    });

    test('orders by counter within the same wall time', () {
      final a = Hlc(1000, 1, 'z');
      final b = Hlc(1000, 2, 'a');
      expect(b.compareTo(a), greaterThan(0));
      expect(b >= a, isTrue);
      expect(a <= b, isTrue);
    });

    test('breaks ties on the device id so the order is total', () {
      final a = Hlc(1000, 1, 'aaa');
      final b = Hlc(1000, 1, 'bbb');
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(a), greaterThan(0));
      expect(a.compareTo(a), 0);
    });

    test('plain string comparison of .value matches compareTo', () {
      final samples = <Hlc>[
        Hlc(0, 0, 'a'),
        Hlc(0, 1, 'a'),
        Hlc(0, 1, 'b'),
        Hlc(999, 99999, 'a'),
        Hlc(1000, 0, 'a'),
        Hlc(1000, 0, 'b'),
        Hlc(1700000000000, 12345, 'device-1'),
        Hlc(1700000000000, 12345, 'device-2'),
        Hlc(1700000000001, 0, 'device-1'),
      ];
      for (final x in samples) {
        for (final y in samples) {
          final byValue = x.value.compareTo(y.value);
          final byCompare = x.compareTo(y);
          expect(
            byValue.sign,
            byCompare.sign,
            reason: 'string order must match numeric order for '
                '${x.value} vs ${y.value}',
          );
        }
      }
    });
  });

  group('HlcClock.next', () {
    test('starts at counter 1 and increments inside the same millisecond',
        () {
      final clock = HlcClock(deviceId: 'dev', nowMs: () => 1000);
      final first = clock.next();
      expect(first.wallMs, 1000);
      expect(first.counter, 1);
      final second = clock.next();
      expect(second.wallMs, 1000);
      expect(second.counter, 2);
      expect(second > first, isTrue);
    });

    test('resets the counter when the wall clock advances', () {
      var now = 1000;
      final clock = HlcClock(deviceId: 'dev', nowMs: () => now);
      expect(clock.next().counter, 1);
      now = 2000;
      final next = clock.next();
      expect(next.wallMs, 2000);
      expect(next.counter, 1);
    });

    test('never moves backwards when the wall clock jumps back', () {
      var now = 5000;
      final clock = HlcClock(deviceId: 'dev', nowMs: () => now);
      final first = clock.next();
      now = 1000; // the wall clock moved 4 seconds into the past
      final second = clock.next();
      expect(second.wallMs, 5000);
      expect(second.counter, first.counter + 1);
      expect(second > first, isTrue);
    });

    test('rolls the counter over into the next wall millisecond', () {
      final clock = HlcClock(
        deviceId: 'dev',
        last: Hlc(1000, 99999, 'dev'),
        nowMs: () => 1000,
      );
      final next = clock.next();
      expect(next.wallMs, 1001);
      expect(next.counter, 0);
      expect(next > Hlc(1000, 99999, 'dev'), isTrue);
    });

    test('persists the last value in the returned clock state', () {
      final clock = HlcClock(deviceId: 'dev', nowMs: () => 1000);
      final a = clock.next();
      expect(clock.last, a);
      final b = clock.next();
      expect(clock.last, b);
    });
  });

  group('HlcClock.observe', () {
    test('advances the local clock past a remote clock', () {
      final clock = HlcClock(deviceId: 'local', nowMs: () => 1000);
      final observed = clock.observe(Hlc(2000, 5, 'remote'));
      expect(observed.wallMs, 2000);
      expect(observed.counter, 6);
      expect(observed.deviceId, 'local');
      // The next local event still sorts after the observed one.
      final next = clock.next();
      expect(next > observed, isTrue);
    });

    test('advances past a remote clock that is 10 minutes in the future', () {
      final clock = HlcClock(deviceId: 'local', nowMs: () => 1000);
      final remote = Hlc(1000 + 10 * 60 * 1000, 1, 'remote');
      final observed = clock.observe(remote);
      expect(observed.wallMs, remote.wallMs);
      expect(observed.counter, remote.counter + 1);
      expect(observed > remote, isTrue);
      // Even though the local wall clock is 10 minutes behind, the local
      // clock must not move backwards.
      final next = clock.next();
      expect(next.wallMs, remote.wallMs);
      expect(next > observed, isTrue);
    });

    test('keeps the local clock when it is 10 minutes ahead of the remote',
        () {
      final clock = HlcClock(deviceId: 'local', nowMs: () => 2000000);
      final observed = clock.observe(Hlc(1000, 3, 'remote'));
      expect(observed.wallMs, 2000000);
      expect(observed.deviceId, 'local');
      expect(observed > Hlc(1000, 3, 'remote'), isTrue);
    });

    test('takes the highest counter when both clocks share the wall time',
        () {
      final clock = HlcClock(
        deviceId: 'local',
        last: Hlc(1000, 3, 'local'),
        nowMs: () => 1000,
      );
      final observed = clock.observe(Hlc(1000, 7, 'remote'));
      expect(observed.wallMs, 1000);
      expect(observed.counter, 8);
    });

    test('observeEvent never moves the clock backwards', () {
      final clock = HlcClock(deviceId: 'local', nowMs: () => 1000);
      final high = clock.observeEvent(Hlc(5000, 1, 'remote'));
      expect(high.wallMs, 5000);
      final low = clock.observeEvent(Hlc(1000, 1, 'remote'));
      expect(low.wallMs, 5000, reason: 'an older remote HLC must not win');
      expect(clock.last, high);
    });

    test('observeEvent on a fresh clock adopts the remote value', () {
      final clock = HlcClock(deviceId: 'local', nowMs: () => 1000);
      final h = clock.observeEvent(Hlc(4242, 9, 'remote'));
      expect(h.wallMs, 4242);
      expect(h.counter, 9);
    });
  });

  group('HLC helpers', () {
    test('compareHlcValues never throws and sorts malformed values first', () {
      expect(compareHlcValues(null, null), 0);
      expect(compareHlcValues('garbage', null), greaterThan(0));
      expect(compareHlcValues(null, 'garbage'), lessThan(0));
      expect(compareHlcValues('garbage', 'garbage'), 0);
      // A malformed value never beats a valid one.
      expect(
        compareHlcValues('garbage', hlcValue(1, 1, 'a')),
        lessThan(0),
      );
      expect(
        compareHlcValues(hlcValue(1, 1, 'a'), 'garbage'),
        greaterThan(0),
      );
      expect(
        compareHlcValues(hlcValue(2000, 1, 'a'), hlcValue(1000, 1, 'a')),
        greaterThan(0),
      );
      expect(
        compareHlcValues(hlcValue(1000, 1, 'a'), hlcValue(1000, 2, 'a')),
        lessThan(0),
      );
    });

    test('HlcFormat rejects malformed HLC strings', () {
      expect(HlcFormat.isInvalid(hlcValue(1000, 1, 'a')), isFalse);
      expect(HlcFormat.isInvalid('nope'), isTrue);
      expect(HlcFormat.isInvalid('1000-1-a'), isTrue);
      expect(HlcFormat.isInvalid('000000000001000-00001-a'), isFalse);
      expect(HlcFormat.isInvalid('000000000001000-100000-a'), isTrue);
      expect(HlcFormat.isInvalid('000000000001000-00001-'), isTrue);
    });
  });
}
