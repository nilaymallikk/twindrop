/// Display formatting for timestamps. Pure functions with an injectable `now`
/// so widget and unit tests are deterministic.
library;

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int value) => value.toString().padLeft(2, '0');

String _dayKey(DateTime time) => '${time.year}-${time.month}-${time.day}';

/// `14:02` in local time (24-hour clock).
String tdClockLabel(int epochMs) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
  return '${_two(time.hour)}:${_two(time.minute)}';
}

/// Chat date separator: `Today`, `Yesterday`, `12 Oct`, or `12 Oct 2025` when
/// the year differs from [now].
String tdDateSeparatorLabel(int epochMs, {DateTime? now}) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
  final reference = (now ?? DateTime.now()).toLocal();
  final today = DateTime(reference.year, reference.month, reference.day);
  final day = DateTime(time.year, time.month, time.day);
  final difference = today.difference(day).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  final base = '${time.day} ${_months[time.month - 1]}';
  return time.year == reference.year ? base : '$base ${time.year}';
}

/// Short relative label used under note cards (`just now`, `2h ago`, `12 Oct`).
String tdRelativeLabel(int epochMs, {DateTime? now}) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
  final reference = (now ?? DateTime.now()).toLocal();
  final diff = reference.difference(time);
  if (diff.isNegative || diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24 &&
      reference.day == time.day &&
      reference.month == time.month &&
      reference.year == time.year) {
    return '${diff.inHours}h ago';
  }
  final base = '${time.day} ${_months[time.month - 1]}';
  return time.year == reference.year ? base : '$base ${time.year}';
}

/// Full local timestamp for diagnostics: `2026-10-21 14:02`.
String tdFullTimestamp(int epochMs) {
  final time = DateTime.fromMillisecondsSinceEpoch(epochMs).toLocal();
  return '${time.year}-${_two(time.month)}-${_two(time.day)} '
      '${_two(time.hour)}:${_two(time.minute)}';
}

/// Wall-clock for pair-session expiry: `4:32 left`.
String tdCountdownLabel(Duration remaining) {
  final clamped = remaining.isNegative ? Duration.zero : remaining;
  final minutes = clamped.inMinutes;
  final seconds = clamped.inSeconds % 60;
  return '$minutes:${_two(seconds)} left';
}

/// Groups chat entries by local day for date separators. Returned keys are
/// `today`-style labels in chronological order of appearance.
List<String> tdDateKeys(Iterable<int> createdAtMs) => <String>{
  for (final ms in createdAtMs)
    _dayKey(DateTime.fromMillisecondsSinceEpoch(ms).toLocal()),
}.toList();
