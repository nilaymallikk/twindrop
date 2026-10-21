import '../db/database.dart';
import '../db/store_ops.dart';
import '../models/enums.dart';
import '../models/errors.dart';
import '../models/item.dart';
import 'dart:convert';

import '../util/hashing.dart';
import '../util/logger.dart';
import '../validators/validators.dart';
import 'chat_service.dart';
import 'notepad_service.dart';
import 'service_base.dart';
import 'settings_store.dart';

enum ShareOutcome {
  savedToNotepad,
  sentAsChat,
  duplicate,
  needsChoice,
}

class ShareResult {
  const ShareResult({
    required this.outcome,
    required this.action,
    this.item,
    this.deduplicated = false,
  });

  final ShareOutcome outcome;
  final ShareDefaultAction action;
  final Item? item;

  /// True when the same URL was shared inside the dedupe window (`SHARE-007`).
  final bool deduplicated;

  bool get hasItem => item != null;
}

/// Android share target intake (`SHARE-002`..`SHARE-008`).
///
/// Persists locally before any network call (all writes go through the local
/// services), deduplicates the same URL inside [dedupeWindow], and reports a
/// truthful status based on whether the item is queued for a paired peer.
class ShareIngest extends CoreService {
  ShareIngest({
    required super.db,
    required super.clock,
    required super.bus,
    required super.logger,
    required NotepadService notepad,
    required ChatService chat,
    required SettingsStore settings,
    DateTime Function()? now,
    Duration dedupeWindow = const Duration(seconds: 10),
  })  : _notepad = notepad,
        _chat = chat,
        _settings = settings,
        _now = now ?? DateTime.now,
        _dedupeWindow = dedupeWindow;

  final NotepadService _notepad;
  final ChatService _chat;
  final SettingsStore _settings;
  final DateTime Function() _now;
  final Duration _dedupeWindow;

  final Map<String, _DedupeEntry> _recent = <String, _DedupeEntry>{};

  /// Ingest shared text/link. [action] overrides the stored default action.
  Future<ShareResult> ingestText({
    required String text,
    String? sourceApp,
    ShareDefaultAction? action,
  }) async {
    if (text.trim().isEmpty) {
      throw const ValidationError('only text and links can be shared');
    }
    final effectiveAction = action ?? await _settings.shareDefaultAction();
    if (effectiveAction == ShareDefaultAction.ask) {
      return const ShareResult(
        outcome: ShareOutcome.needsChoice,
        action: ShareDefaultAction.ask,
      );
    }

    final link = firstValidUrl(text);
    if (link != null) {
      final now = _now();
      _recent.removeWhere((_, e) => now.difference(e.at) > _dedupeWindow);
      final seen = _recent[link.url];
      if (seen != null && now.difference(seen.at) <= _dedupeWindow) {
        final existing = await db.itemById(seen.itemId);
        if (existing != null) {
          _recent[link.url] = _DedupeEntry(now, existing.id);
          return ShareResult(
            outcome: ShareOutcome.duplicate,
            action: effectiveAction,
            item: existing,
            deduplicated: true,
          );
        }
      }
    }

    final Item item;
    final ShareOutcome outcome;
    if (effectiveAction == ShareDefaultAction.chat) {
      item = await _chat.sendMessage(text, sourceApp: sourceApp);
      outcome = ShareOutcome.sentAsChat;
    } else {
      item = await _notepad.createNote(
        text: text,
        sourceApp: sourceApp,
        categoryId: 'inbox',
      );
      outcome = ShareOutcome.savedToNotepad;
    }
    if (link != null) {
      _recent[link.url] = _DedupeEntry(_now(), item.id);
    }
    logger.info('share ingested', fields: {'outcome': outcome.name});
    return ShareResult(outcome: outcome, action: effectiveAction, item: item);
  }

  /// Unsupported payload (image/file) must not crash and must tell the user
  /// text/links only (`SHARE-008`).
  Never rejectUnsupported({String? mimeType}) {
    throw const ValidationError('only text and links can be shared');
  }

  /// "Also send as chat" from the share panel (`SHARE-003`).
  Future<Item> alsoSendAsChat(Item note) async {
    final message = await _chat.sendMessage(
      note.url ?? note.text,
      sourceApp: note.sourceApp,
    );
    return message;
  }

  /// "Change category" from the share panel; delegates to the notepad service.
  Future<Item> changeCategory(Item note, String categoryId) =>
      _notepad.moveNote(note.id, categoryId);

  /// "Undo" from the share panel: removes the just-created item.
  Future<void> undo(ShareResult result) async {
    final item = result.item;
    if (item == null) return;
    if (result.outcome == ShareOutcome.sentAsChat || item.isMessage) {
      await _chat.deleteMessage(item.id);
    } else {
      await _notepad.deleteNote(item.id);
    }
    _recent.removeWhere((_, e) => e.itemId == item.id);
  }

  /// True when at least one non-revoked peer is paired (used for "Saved — will
  /// sync when the desktop is online", `SHARE-005`).
  Future<bool> willSync() async {
    final peers = await db.peerRows(includeRevoked: false);
    return peers.isNotEmpty;
  }

  /// Stable key for the dedupe window (exposed for tests).
  static String dedupeKeyFor(String text) =>
      firstValidUrl(text)?.url ?? sha256Hex(utf8.encode(text));
}

class _DedupeEntry {
  const _DedupeEntry(this.at, this.itemId);
  final DateTime at;
  final String itemId;
}
