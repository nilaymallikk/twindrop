import 'dart:convert';

import '../models/errors.dart';

/// Input validators and canonicalisation rules (`docs/04-data-model.md`
/// §Validation, `docs/08-security-privacy.md`).

/// Hard limits (bytes are UTF-8 bytes; reject, never truncate).
const int maxMessageBytes = 64 * 1024;
const int maxNoteBytes = 256 * 1024;
const int maxTitleChars = 200;
const int maxCategoryNameChars = 60;
const int maxFrameBytes = 1024 * 1024;

/// URL schemes accepted as links. Anything else stays plain text (SEC-004).
const Set<String> allowedUrlSchemes = {'http', 'https'};

/// A parsed link: the URL we will store as a link plus the raw text left for
/// display.
class ExtractedLink {
  const ExtractedLink({required this.url, required this.raw});

  /// Normalised absolute http(s) URL (trailing punctuation removed).
  final String url;

  /// The exact substring found in the text, before trimming punctuation.
  final String raw;
}

final RegExp _urlCandidate = RegExp(
  r'https?://[^\s<>"' r"'" r'`]+',
  caseSensitive: false,
);

/// Trailing punctuation that is almost always sentence punctuation, not part
/// of the URL.
const String _trailingPunctuation = '.,;:!?)]}\'"»«';

/// True if [value] is an absolute http/https URL with a host.
bool isValidWebUrl(String? value) {
  if (value == null) return false;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
  if (!allowedUrlSchemes.contains(uri.scheme.toLowerCase())) return false;
  // Reject userinfo that tries to look like another host (phishing-ish), and
  // reject control characters a URL never legitimately contains.
  if (uri.userInfo.isNotEmpty) return false;
  if (trimmed.contains(RegExp(r'[\u0000-\u001f\u007f]'))) return false;
  for (final r in uri.queryParametersAll.entries) {
    for (final v in r.value) {
      if (v.contains(RegExp(r'[\u0000-\u001f\u007f]'))) return false;
    }
  }
  return true;
}

/// Extract the first valid `http`/`https` URL from [text], or null.
ExtractedLink? firstValidUrl(String text) {
  for (final match in _urlCandidate.allMatches(text)) {
    final raw = match.group(0)!;
    var candidate = raw;
    while (candidate.isNotEmpty &&
        _trailingPunctuation.contains(candidate[candidate.length - 1])) {
      candidate = candidate.substring(0, candidate.length - 1);
    }
    if (candidate.isEmpty) continue;
    if (!isValidWebUrl(candidate)) continue;
    final uri = Uri.parse(candidate);
    return ExtractedLink(url: uri.toString(), raw: raw);
  }
  return null;
}

/// Does [text] contain at least one http/https URL?
bool containsWebUrl(String text) => firstValidUrl(text) != null;

/// Strip Instagram tracking params (`igsh`, `igshid`) when clean-links is on.
/// The original text is kept by the caller; this only affects the stored link.
String cleanInstagramUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;
  final host = uri.host.toLowerCase();
  if (host != 'instagram.com' && !host.endsWith('.instagram.com')) return url;
  final params = Map<String, List<String>>.from(uri.queryParametersAll);
  params.remove('igsh');
  params.remove('igshid');
  if (params.length == uri.queryParametersAll.length) return url;
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
    queryParameters:
        params.isEmpty ? null : params.map((k, v) => MapEntry(k, v.join(','))),
    fragment: uri.hasFragment ? uri.fragment : null,
  ).toString();
}

/// Trim + collapse internal whitespace + lowercase; uniqueness key for
/// categories (case-insensitive).
String normalizeCategoryName(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Category name is valid when trimmed it is 1..60 characters and not blank.
bool isValidCategoryName(String name) {
  final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  return trimmed.isNotEmpty && trimmed.length <= maxCategoryNameChars;
}

/// Message/note text limits measured in UTF-8 bytes.
bool isValidMessageText(String text) =>
    text.trim().isNotEmpty && utf8.encode(text).length <= maxMessageBytes;

bool isValidNoteText(String text) => utf8.encode(text).length <= maxNoteBytes;

bool isValidTitle(String? title) =>
    title == null || title.length <= maxTitleChars;

/// UTF-8 validation for a byte payload received from the wire.
String? decodeUtf8Strict(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// Reject text containing lone surrogates (invalid UTF-16 that cannot be
/// encoded as UTF-8).
///
/// `utf8.encode` does not throw for a lone surrogate — it silently replaces
/// it with U+FFFD — so the code units are inspected directly.
bool isWellFormedUnicode(String text) {
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      // High surrogate: it must be followed by a low surrogate.
      if (i + 1 >= text.length) return false;
      final next = text.codeUnitAt(i + 1);
      if (next < 0xDC00 || next > 0xDFFF) return false;
      i++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      // Low surrogate without a preceding high surrogate.
      return false;
    }
  }
  return true;
}

/// Validators throw the typed [ValidationError], not a raw exception: every
/// failure that can reach the UI or the wire goes through the error model in
/// `models/errors.dart` (`docs/03` §Error boundary).
void validateMessageText(String text) {
  if (!isWellFormedUnicode(text)) {
    throw const ValidationError('text is not valid UTF-8');
  }
  if (text.trim().isEmpty) {
    throw const ValidationError('text is empty');
  }
  if (utf8.encode(text).length > maxMessageBytes) {
    throw const ValidationError('text too large');
  }
}

void validateNoteText(String text) {
  if (!isWellFormedUnicode(text)) {
    throw const ValidationError('text is not valid UTF-8');
  }
  if (utf8.encode(text).length > maxNoteBytes) {
    throw const ValidationError('text too large');
  }
}

void validateTitle(String? title) {
  if (title != null && title.length > maxTitleChars) {
    throw const ValidationError('title too long');
  }
}

void validateCategoryName(String name) {
  if (!isValidCategoryName(name)) {
    throw const ValidationError('invalid category name');
  }
}
