import '../models/enums.dart';
import '../models/errors.dart';
import '../models/item.dart';
import '../util/hashing.dart';
import '../util/ids.dart';
import '../validators/validators.dart';

/// Builds a new immutable item row from user input (`docs/04` §Validation).
///
/// * Messages and notes both extract the first valid `http(s)` URL from the
///   text; anything else stays plain text and is never linkified.
/// * The Instagram tracking-parameter cleanup only affects the stored link;
///   [text] always keeps the original string.
/// * Throws [ValidationError] for oversize/non-UTF-8/empty payloads.
Item buildNewItem({
  required ItemType type,
  required String text,
  String? title,
  String? url,
  String? categoryId,
  String? sourceApp,
  String? sourceItemId,
  required String deviceId,
  required String deviceName,
  required String hlc,
  required int createdAt,
  String? id,
  bool cleanInstagramLinks = true,
}) {
  if (type == ItemType.message) {
    validateMessageText(text);
    if (categoryId != null) {
      throw const ValidationError('messages cannot have a category');
    }
  } else {
    validateNoteText(text);
    if (text.trim().isEmpty && (title == null || title!.trim().isEmpty) &&
        (url == null || url!.trim().isEmpty)) {
      throw const ValidationError('note is empty');
    }
  }
  validateTitle(title);

  var storedUrl = url?.trim();
  if (storedUrl != null && storedUrl.isEmpty) storedUrl = null;
  if (storedUrl != null) {
    if (!isValidWebUrl(storedUrl)) {
      throw const ValidationError('not an http(s) link');
    }
  } else {
    storedUrl = firstValidUrl(text)?.url;
  }
  if (storedUrl != null && cleanInstagramLinks) {
    storedUrl = cleanInstagramUrl(storedUrl);
  }

  final kind = storedUrl != null ? ItemKind.link : ItemKind.text;
  final contentHash =
      contentHashOf(text: text, title: title, url: storedUrl);
  return Item(
    id: id ?? newId(),
    type: type,
    kind: kind,
    text: text,
    title: title,
    url: storedUrl,
    sourceApp: sourceApp,
    categoryId: type == ItemType.message ? null : categoryId,
    originDevice: deviceId,
    originName: deviceName,
    sourceItemId: sourceItemId,
    createdAt: createdAt,
    contentHash: contentHash,
    prevHash: null,
    contentHlc: hlc,
    pinned: false,
    deleted: false,
    deletedHlc: null,
    metaHlc: hlc,
    restored: false,
    isConflictCopy: false,
  );
}

/// Update the content group of an existing note (text/title/url) keeping the
/// hash chain intact (`prev_hash` = previous content hash).
Item editedContent(
  Item current, {
  String? text,
  String? title,
  String? url,
  bool clearTitle = false,
  bool clearUrl = false,
  required String hlc,
  bool cleanInstagramLinks = true,
}) {
  final newText = text ?? current.text;
  validateNoteText(newText);
  final newTitle = clearTitle ? null : (title ?? current.title);
  validateTitle(newTitle);
  var newUrl = clearUrl ? null : (url ?? current.url);
  if (url != null && url.trim().isNotEmpty && !isValidWebUrl(url.trim())) {
    throw const ValidationError('not an http(s) link');
  }
  if (url != null && url.trim().isEmpty) newUrl = null;
  if (newUrl == null && url == null && !clearUrl) {
    // Editing text may introduce or remove the first link.
    newUrl = firstValidUrl(newText)?.url;
  }
  if (newUrl != null && cleanInstagramLinks) {
    newUrl = cleanInstagramUrl(newUrl);
  }
  if (newText.trim().isEmpty &&
      (newTitle == null || newTitle.trim().isEmpty) &&
      newUrl == null) {
    throw const ValidationError('note is empty');
  }
  return current.copyWith(
    text: newText,
    title: newTitle,
    url: newUrl,
    clearTitle: newTitle == null,
    clearUrl: newUrl == null,
    kind: newUrl != null ? ItemKind.link : ItemKind.text,
    contentHash: contentHashOf(text: newText, title: newTitle, url: newUrl),
    prevHash: current.contentHash,
    contentHlc: hlc,
  );
}
