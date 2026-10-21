import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// New lowercase UUIDv7 id (time-ordered, `docs/04-data-model.md`).
///
/// UUIDv7 is used for every entity so ids sort by creation time, which keeps
/// cursor-sync pages and conflict-copy ids deterministic across devices.
String newId() => _uuid.v7().toLowerCase();

/// Deterministic UUIDv5 id used for conflict copies so both devices create the
/// exact same copy row and never duplicate it (SYNC-005).
String deterministicId(String namespace, String name) =>
    _uuid.v5(namespace, name).toLowerCase();
