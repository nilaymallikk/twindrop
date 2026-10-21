import 'dart:math';

/// Hybrid Logical Clock (HLC), `docs/04-data-model.md`.
///
/// Encoded as `<wallMs 15-digit>-<counter 5-digit>-<deviceId>` so that plain
/// string comparison is a total order. Wall time and counter are fixed-width,
/// therefore lexicographic order matches (wall, counter) order for all times
/// until year 33658.
class Hlc implements Comparable<Hlc> {
  const Hlc(this.wallMs, this.counter, this.deviceId);

  final int wallMs;
  final int counter;
  final String deviceId;

  static final RegExp _re = RegExp(r'^(\d{15})-(\d{5})-(.+)$');

  String get value =>
      '${wallMs.toString().padLeft(15, '0')}-'
      '${counter.toString().padLeft(5, '0')}-$deviceId';

  static Hlc parse(String s) {
    final m = _re.firstMatch(s);
    if (m == null) throw FormatException('invalid HLC: $s');
    return Hlc(int.parse(m.group(1)!), int.parse(m.group(2)!), m.group(3)!);
  }

  static Hlc? tryParse(String? s) {
    if (s == null) return null;
    try {
      return parse(s);
    } on FormatException {
      return null;
    }
  }

  @override
  int compareTo(Hlc other) {
    if (wallMs != other.wallMs) return wallMs.compareTo(other.wallMs);
    if (counter != other.counter) return counter.compareTo(other.counter);
    return deviceId.compareTo(other.deviceId);
  }

  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator <(Hlc other) => compareTo(other) < 0;
  bool operator >=(Hlc other) => compareTo(other) >= 0;
  bool operator <=(Hlc other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.wallMs == wallMs &&
      other.counter == counter &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(wallMs, counter, deviceId);

  @override
  String toString() => value;
}

/// Monotonic clock producing HLC strings, tolerant of wall-clock skew in both
/// directions (SYNC-010).
///
/// Call [next] for local events and [observe] for every remote HLC seen when
/// applying a change page. The last value is persisted (settings key
/// `hlc.last`) and passed back through [last] on restart.
class HlcClock {
  HlcClock({required this.deviceId, this.last, int Function()? nowMs})
    : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final String deviceId;
  final int Function() _nowMs;
  Hlc? last;
  static const int _maxCounter = 99999;

  Hlc next() {
    final now = _nowMs();
    final l = last;
    int wall;
    int counter;
    if (l == null || now > l.wallMs) {
      wall = now;
      counter = 1;
    } else {
      // Same or earlier wall time: keep the clock monotonic.
      wall = l.wallMs;
      counter = l.counter + 1;
      if (counter > _maxCounter) {
        wall += 1;
        counter = 0;
      }
    }
    final h = Hlc(wall, counter, deviceId);
    last = h;
    return h;
  }

  /// Observe a remote HLC and advance the local clock beyond it.
  Hlc observe(Hlc remote) {
    final now = _nowMs();
    final l = last;
    final wall = [now, l?.wallMs ?? now, remote.wallMs].reduce(max);
    int counter;
    if (l != null && wall == l.wallMs && wall == remote.wallMs) {
      counter = max(l.counter, remote.counter) + 1;
    } else if (l != null && wall == l.wallMs) {
      counter = l.counter + 1;
    } else if (wall == remote.wallMs) {
      counter = remote.counter + 1;
    } else {
      counter = 0;
    }
    if (counter > _maxCounter) {
      // Extremely unlikely; bump wall time and reset the counter.
      return observeEvent(Hlc(wall + 1, 0, deviceId));
    }
    final h = Hlc(wall, counter, deviceId);
    last = h;
    return h;
  }

  /// Set the clock to a known value (e.g. after receiving a page whose maximum
  /// HLC is below our current clock).
  Hlc observeEvent(Hlc h) {
    if (last == null || h > last!) last = h;
    return last!;
  }
}
