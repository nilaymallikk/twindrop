import 'dart:io';

/// Redaction level for [Logger]. Logs never contain message/note text, full
/// URLs, tokens, QR payloads or keys (`docs/08` §Logging); these levels only
/// control how much *network/technical* detail is allowed.
enum RedactionLevel {
  /// Host:port, seq numbers, error categories allowed (`docs/08`).
  standard,

  /// Also redacts host/IP details; useful for diagnostics exports.
  strict,
}

enum LogLevel { debug, info, warn, error }

/// Minimal structured logger with mandatory redaction.
///
/// The core never logs payloads, so this class additionally scrubs accidental
/// leaks: URLs, long hex/base64 runs (tokens, fingerprints) and, in
/// [RedactionLevel.strict], IP addresses. A test greps log output for secrets.
class Logger {
  Logger({
    this.level = LogLevel.info,
    this.redaction = RedactionLevel.standard,
    void Function(String line)? sink,
  }) : _sink = sink ?? _stderrSink;

  final LogLevel level;
  final RedactionLevel redaction;
  final void Function(String line) _sink;

  static void _stderrSink(String line) => stderr.writeln(line);

  /// A logger that drops everything (tests / phone UI default).
  static final Logger silent =
      Logger(level: LogLevel.error, sink: (_) {});

  static final RegExp _url = RegExp(r'\bhttps?://[^\s]+', caseSensitive: false);
  static final RegExp _hexRun = RegExp(r'\b[0-9a-fA-F]{20,}\b');
  static final RegExp _base64Run = RegExp(r'\b[A-Za-z0-9+/_-]{32,}={0,2}\b');
  static final RegExp _ipv4 = RegExp(r'\b\d{1,3}(?:\.\d{1,3}){3}\b');
  static final RegExp _control = RegExp(r'[\u0000-\u001f\u007f]');

  /// Redact a value for logging. Total function: never throws.
  String redactValue(String value) {
    var out = value.replaceAll(_control, ' ');
    out = out.replaceAll(_url, '[url]');
    out = out.replaceAll(_hexRun, '[redacted]');
    out = out.replaceAll(_base64Run, '[redacted]');
    if (redaction == RedactionLevel.strict) {
      out = out.replaceAll(_ipv4, '[host]');
    }
    return out;
  }

  bool _enabled(LogLevel l) => l.index >= level.index;

  void log(LogLevel l, String message, {Map<String, Object?>? fields}) {
    if (!_enabled(l)) return;
    final sb = StringBuffer()
      ..write(DateTime.now().toUtc().toIso8601String())
      ..write(' ')
      ..write(l.name.toUpperCase().padRight(5))
      ..write(' ')
      ..write(redactValue(message));
    if (fields != null && fields.isNotEmpty) {
      sb.write(' {');
      var first = true;
      for (final e in fields.entries) {
        if (!first) sb.write(', ');
        first = false;
        final raw = e.value is String ? e.value as String : '${e.value}';
        sb
          ..write(e.key)
          ..write('=')
          ..write(redactValue(raw));
      }
      sb.write('}');
    }
    _sink(sb.toString());
  }

  void debug(String message, {Map<String, Object?>? fields}) =>
      log(LogLevel.debug, message, fields: fields);
  void info(String message, {Map<String, Object?>? fields}) =>
      log(LogLevel.info, message, fields: fields);
  void warn(String message, {Map<String, Object?>? fields}) =>
      log(LogLevel.warn, message, fields: fields);
  void error(String message, {Map<String, Object?>? fields}) =>
      log(LogLevel.error, message, fields: fields);

  /// Log a typed failure plus its cause *type only* (never a stack trace with
  /// interpolated payloads).
  void failure(TwinDropLoggerError e) =>
      error(e.category, fields: {'error': e.detail});
}

/// Small indirection so [Logger.failure] does not need to import the error
/// model in call sites that only have a category and a safe detail string.
class TwinDropLoggerError {
  const TwinDropLoggerError(this.category, [this.detail = '']);
  final String category;
  final String detail;
}
