import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';

void main() {
  group('Logger redaction', () {
    test('removes URLs from a message', () {
      final logger = Logger(sink: (_) {});
      final redacted = logger.redactValue(
        'opening https://example.com/secret?token=abc now',
      );
      expect(redacted, isNot(contains('example.com')));
      expect(redacted, contains('[url]'));
    });

    test('removes long hex runs (fingerprints, token hashes)', () {
      final logger = Logger(sink: (_) {});
      final redacted = logger.redactValue('fp ${'a' * 64} end');
      expect(redacted, isNot(contains('a' * 64)));
      expect(redacted, contains('[redacted]'));
    });

    test('removes long base64 runs (device tokens, pairing payloads)', () {
      final logger = Logger(sink: (_) {});
      final token = 'A' * 43;
      final redacted = logger.redactValue('bearer $token');
      expect(redacted, isNot(contains(token)));
      expect(redacted, contains('[redacted]'));
    });

    test('removes control characters', () {
      final logger = Logger(sink: (_) {});
      final redacted = logger.redactValue('a\u0000b\u001fc');
      expect(redacted, isNot(contains('\u0000')));
      expect(redacted, isNot(contains('\u001f')));
    });

    test('keeps the host:port detail in the standard level', () {
      final logger = Logger(sink: (_) {});
      final redacted = logger.redactValue('host 192.168.1.10:47321');
      expect(redacted, contains('192.168.1.10'));
      expect(redacted, contains('47321'));
    });

    test('strict mode also removes IP addresses', () {
      final logger = Logger(
        redaction: RedactionLevel.strict,
        sink: (_) {},
      );
      final redacted = logger.redactValue('host 192.168.1.10:47321');
      expect(redacted, isNot(contains('192.168.1.10')));
      expect(redacted, contains('[host]'));
      expect(redacted, contains('47321'));
    });

    test('redactValue never throws', () {
      final logger = Logger(sink: (_) {});
      expect(() => logger.redactValue(''), returnsNormally);
      expect(() => logger.redactValue('\u0000\u0001'), returnsNormally);
    });
  });

  group('Logger output', () {
    test('writes one line per call to the sink', () {
      final lines = <String>[];
      final logger = Logger(sink: lines.add);
      logger.info('hello');
      logger.warn('careful');
      logger.error('broken');
      expect(lines.length, 3);
      expect(lines.first, contains('INFO'));
      expect(lines[1], contains('WARN'));
      expect(lines[2], contains('ERROR'));
    });

    test('a URL in a logged field never reaches the sink', () {
      final lines = <String>[];
      final logger = Logger(sink: lines.add);
      logger.info('share ingested', fields: {
        'url': 'https://www.instagram.com/reel/ABC/?igsh=SECRET',
      });
      expect(lines.single, isNot(contains('instagram')));
      expect(lines.single, isNot(contains('SECRET')));
    });

    test('a token in a logged field never reaches the sink', () {
      final lines = <String>[];
      final logger = Logger(sink: (_) {});
      final token = DeviceTokens.issue();
      logger.info('auth', fields: {'token': token});
      expect(lines, isEmpty);
      expect(logger.redactValue(token), isNot(contains(token)));
    });

    test('respects the level filter', () {
      final lines = <String>[];
      final logger = Logger(level: LogLevel.warn, sink: lines.add);
      logger.debug('noise');
      logger.info('noise');
      logger.warn('important');
      expect(lines.length, 1);
      expect(lines.single, contains('important'));
    });

    test('the silent logger writes nothing', () {
      final lines = <String>[];
      final logger = Logger(level: LogLevel.debug, sink: lines.add);
      logger.debug('x');
      logger.error('y');
      expect(lines.length, 2);
      expect(Logger.silent, isNotNull);
    });
  });
}
