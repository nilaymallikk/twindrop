import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../models/item.dart';
import 'tables.dart';

part 'database.g.dart';

/// The local SQLite replica. Both devices run the same schema (local-first,
/// SYNC-001). The desktop and phone use their own file path; tests use
/// [AppDatabase.memory].
@DriftDatabase(
  tables: [
    Peers,
    Categories,
    Items,
    ChangeLogs,
    PeerDeliveries,
    Quarantines,
    AppliedRemotes,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor e) : super(e);

  /// In-memory database for tests and for `tool/fake_peer.dart`.
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  /// Opens (or creates) the replica at [path]. WAL mode is set in [migration];
  /// parent directories must exist.
  factory AppDatabase.openAt(String path) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    return AppDatabase(
      NativeDatabase.createInBackground(file, logStatements: false),
    );
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createFts();
      await _createIndexes();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA journal_mode=WAL');
      await customStatement('PRAGMA foreign_keys=ON');
      await customStatement('PRAGMA synchronous=NORMAL');
      await customStatement('PRAGMA busy_timeout=5000');
    },
  );

  Future<void> _createFts() async {
    await customStatement(
      'CREATE VIRTUAL TABLE IF NOT EXISTS items_fts USING fts5('
      'itemId UNINDEXED, title, text, url)',
    );
  }

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_items_type_deleted '
      'ON items(type, deleted, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_items_category '
      'ON items(category_id, deleted)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_change_log_entity '
      'ON change_log(entity_type, entity_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_peer_delivery_item '
      'ON peer_delivery(item_id)',
    );
  }

  // ---- settings (local only) ----

  Future<String?> getSetting(String key) async {
    final row = await (select(
      settings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setSetting(String key, String value) async {
    await into(
      settings,
    ).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
  }

  Future<void> deleteSetting(String key) async {
    await (delete(settings)..where((t) => t.key.equals(key))).go();
  }

  // ---- change log cursor helpers ----

  /// Highest local seq (0 when empty).
  Future<int> lastChangeSeq() async {
    final row = await customSelect(
      'SELECT COALESCE(MAX(seq), 0) AS m FROM change_log',
      readsFrom: {changeLogs},
    ).getSingle();
    return row.read<int>('m');
  }

  // ---- FTS5 (manual maintenance; one row per live item) ----

  Future<void> ftsUpsert(Item item) async {
    await ftsRemove(item.id);
    if (item.deleted) return;
    await customStatement(
      'INSERT INTO items_fts(itemId, title, text, url) VALUES (?, ?, ?, ?)',
      [item.id, item.title ?? '', item.text, item.url ?? ''],
    );
  }

  Future<void> ftsRemove(String itemId) async {
    await customStatement('DELETE FROM items_fts WHERE itemId = ?', [itemId]);
  }

  /// Full-text search over notes/messages. Returns matching item ids ordered by
  /// FTS rank. Malformed FTS queries fall back to a LIKE scan instead of
  /// throwing (SET-004).
  Future<List<String>> ftsSearchIds(String query, {int limit = 100}) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final safe = _ftsQuery(q);
      final rows = await customSelect(
        'SELECT itemId FROM items_fts WHERE items_fts MATCH ? '
        'ORDER BY rank LIMIT ?',
        variables: [Variable(safe), Variable(limit)],
      ).get();
      return rows.map((r) => r.read<String>('itemId')).toList();
    } on Exception {
      final like = '%${q.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      final rows = await customSelect(
        'SELECT itemId FROM items_fts '
        'WHERE title LIKE ? ESCAPE \'\\\' '
        '   OR text LIKE ? ESCAPE \'\\\' '
        '   OR url LIKE ? ESCAPE \'\\\' '
        'LIMIT ?',
        variables: [
          Variable(like),
          Variable(like),
          Variable(like),
          Variable(limit),
        ],
      ).get();
      return rows.map((r) => r.read<String>('itemId')).toList();
    }
  }

  /// Quote each search term and add prefix matching, e.g. `foo bar` ->
  /// `"foo"* "bar"*`. Keeps user input from being parsed as FTS5 syntax.
  static String _ftsQuery(String input) {
    final terms = input
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => '"${t.replaceAll('"', '""')}"*')
        .toList();
    return terms.join(' ');
  }

  // ---- integrity ----

  /// Runs SQLite integrity_check; false means the file is corrupt and the app
  /// must back it up before any recovery (docs/04).
  Future<bool> integrityOk() async {
    try {
      final rows = await customSelect('PRAGMA integrity_check').get();
      return rows.length == 1 && rows.first.data.values.first == 'ok';
    } on Exception {
      return false;
    }
  }

  /// SQLite user_version/schema sanity used by SET-005 migrations.
  Future<int> userVersion() async {
    final row = await customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }
}
