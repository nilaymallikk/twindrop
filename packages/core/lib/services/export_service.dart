import 'dart:convert';

import '../db/database.dart';
import '../db/store_ops.dart';
import '../models/category.dart';
import '../models/enums.dart';
import '../models/item.dart';
import '../services/notepad_service.dart';

/// Exported document plus the suggested file name (the app layer writes the
/// file, core stays filesystem-free for the DB path rules in `docs/04`).
class ExportDocument {
  const ExportDocument({
    required this.fileName,
    required this.content,
    required this.mimeType,
  });

  final String fileName;
  final String content;
  final String mimeType;
}

/// Markdown and JSON export of the notepad (`NOTE-009`).
///
/// Read-only: never mutates the replica, never includes tokens/pins/secrets,
/// and skips tombstones. Conflict copies are exported but flagged.
class ExportService {
  ExportService({
    required AppDatabase db,
    required NotepadService notepad,
    required String deviceName,
    DateTime Function()? now,
  }) : _db = db,
       _notepad = notepad,
       _deviceName = deviceName,
       _now = now ?? DateTime.now;

  final AppDatabase _db;
  final NotepadService _notepad;
  final String _deviceName;
  final DateTime Function() _now;

  Future<ExportDocument> markdown({String? categoryId}) async {
    final categories = await _categories(categoryId);
    final buffer = StringBuffer()
      ..writeln('# TwinDrop Notepad')
      ..writeln()
      ..writeln('Exported ${_iso(_now())} from $_deviceName')
      ..writeln();
    for (final category in categories) {
      final notes = await _notepad.notesForExport(categoryId: category.id);
      buffer
        ..writeln('## ${category.name}')
        ..writeln();
      if (notes.isEmpty) {
        buffer
          ..writeln('_No notes._')
          ..writeln();
        continue;
      }
      for (final note in notes) {
        if (note.title != null && note.title!.trim().isNotEmpty) {
          buffer.writeln('### ${_oneLine(note.title!)}');
        } else if (note.url != null) {
          buffer.writeln('### ${_oneLine(_fallbackTitle(note))}');
        }
        if (note.isConflictCopy) {
          buffer.writeln('_Conflict copy_');
          buffer.writeln();
        }
        if (note.url != null) {
          buffer
            ..writeln(note.url)
            ..writeln();
        }
        if (note.text.trim().isNotEmpty && note.text.trim() != note.url) {
          buffer
            ..writeln(note.text)
            ..writeln();
        }
        buffer
          ..writeln(
            '_${_iso(DateTime.fromMillisecondsSinceEpoch(note.createdAt, isUtc: true))}'
            '${note.pinned ? ' · pinned' : ''}_',
          )
          ..writeln();
      }
    }
    return ExportDocument(
      fileName: 'twindrop-notepad-${_stamp()}.md',
      content: buffer.toString(),
      mimeType: 'text/markdown',
    );
  }

  Future<ExportDocument> json({String? categoryId}) async {
    final categories = await _categories(categoryId);
    final notes = <Map<String, dynamic>>[];
    for (final category in categories) {
      for (final note in await _notepad.notesForExport(
        categoryId: category.id,
      )) {
        notes.add(_noteJson(note));
      }
    }
    final payload = <String, dynamic>{
      'app': 'twindrop',
      'formatVersion': 1,
      'exportedAt': _iso(_now()),
      'deviceName': _deviceName,
      'categories': [
        for (final c in categories)
          {
            'id': c.id,
            'name': c.name,
            if (c.color != null) 'color': c.color,
            'sortOrder': c.sortOrder,
            'isInbox': c.isInbox,
          },
      ],
      'notes': notes,
    };
    return ExportDocument(
      fileName: 'twindrop-notepad-${_stamp()}.json',
      content: const JsonEncoder.withIndent('  ').convert(payload),
      mimeType: 'application/json',
    );
  }

  Future<List<Category>> _categories(String? categoryId) async {
    final categories = await _db.listCategoryRows();
    if (categoryId == null) {
      final inbox = categories.where((c) => c.isInbox).toList();
      final rest = categories.where((c) => !c.isInbox).toList();
      return [...inbox, ...rest];
    }
    return categories.where((c) => c.id == categoryId).toList();
  }

  Map<String, dynamic> _noteJson(Item note) => <String, dynamic>{
    'id': note.id,
    'type': note.type.wire,
    'kind': note.kind.wire,
    'text': note.text,
    if (note.title != null) 'title': note.title,
    if (note.url != null) 'url': note.url,
    if (note.sourceApp != null) 'sourceApp': note.sourceApp,
    if (note.categoryId != null) 'categoryId': note.categoryId,
    if (note.sourceItemId != null) 'sourceItemId': note.sourceItemId,
    'createdAt': _iso(
      DateTime.fromMillisecondsSinceEpoch(note.createdAt, isUtc: true),
    ),
    'pinned': note.pinned,
    'isConflictCopy': note.isConflictCopy,
    'originDevice': note.originDevice,
    'originName': note.originName,
  };

  String _fallbackTitle(Item note) {
    final t = note.text.trim();
    if (t.isEmpty) return 'Note';
    return t.length <= 60 ? t : t.substring(0, 60);
  }

  String _oneLine(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  String _iso(DateTime t) => t.toUtc().toIso8601String();

  String _stamp() => _now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('-', '')
      .split('.')
      .first;
}
