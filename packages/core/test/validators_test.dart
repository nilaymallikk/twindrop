import 'dart:convert';

import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';

void main() {
  group('isValidWebUrl - accepted', () {
    final accepted = <String>[
      'https://example.com',
      'http://example.com',
      'https://example.com/path',
      'https://example.com/path?query=1#fragment',
      'HTTPS://EXAMPLE.COM/Path', // scheme and host are lower-cased
      'https://www.instagram.com/reel/ABC123/?igsh=XYZ&utm_source=ig_web_copy_link',
      'https://xn--exmple-cua.com', // punycode
      'https://192.168.1.10:47321/v1/health',
      'https://example.com:8443/',
    ];
    for (final url in accepted) {
      test('accepts $url', () {
        expect(isValidWebUrl(url), isTrue, reason: url);
      });
    }
  });

  group('isValidWebUrl - rejected', () {
    final rejected = <String, String>{
      'javascript:alert(1)': 'script scheme',
      'JavaScript:alert(1)': 'script scheme, mixed case',
      'file:///etc/passwd': 'local file scheme',
      'data:text/html;base64,PHNjcmlwdD4=': 'data scheme',
      'intent://scan/#Intent;scheme=zxing;end': 'android intent scheme',
      'content://media/external/images/1': 'content scheme',
      'ftp://example.com/file': 'non-web scheme',
      'mailto:someone@example.com': 'mail scheme',
      'tel:+15551234': 'tel scheme',
      'ws://example.com/socket': 'websocket scheme',
      '/relative/path': 'relative path',
      'relative/path.html': 'relative path without leading slash',
      '//example.com/path': 'protocol relative URL',
      'example.com/path': 'host without scheme',
      'www.example.com': 'host without scheme',
      'https://': 'scheme without host',
      'http://': 'scheme without host',
      'https://user:pass@example.com': 'credentials in the URL',
      'https://example.com/\u0000': 'NUL control character',
      'https://example.com/?q=\u0001': 'control character in the query',
      '': 'empty string',
      '   ': 'whitespace only',
    };
    rejected.forEach((url, why) {
      test('rejects $why ($url)', () {
        expect(isValidWebUrl(url), isFalse, reason: url);
      });
    });

    test('rejects null', () {
      expect(isValidWebUrl(null), isFalse);
    });
  });

  group('firstValidUrl - extraction', () {
    test('extracts a plain https URL', () {
      final link = firstValidUrl('look at https://example.com please');
      expect(link, isNotNull);
      expect(link!.url, 'https://example.com');
      expect(link.raw, 'https://example.com');
    });

    test('extracts an Instagram reel URL that carries igsh', () {
      const raw =
          'https://www.instagram.com/reel/ABC123/?igsh=XYZ&utm_source=ig_web_copy_link';
      final link = firstValidUrl('check this $raw');
      expect(link, isNotNull);
      expect(link!.url, raw);
      expect(link.raw, raw);
      expect(link.url, contains('igsh=XYZ'));
    });

    test('keeps the first URL when several are present', () {
      final link = firstValidUrl(
        'first https://one.example then https://two.example',
      );
      expect(link!.url, 'https://one.example');
    });

    test('skips a rejected scheme and finds the next valid URL', () {
      final link = firstValidUrl(
        'danger javascript:alert(1) but real https://ok.example/page',
      );
      expect(link!.url, 'https://ok.example/page');
    });

    test('returns null when the text has no web URL', () {
      expect(firstValidUrl('nothing here'), isNull);
      expect(firstValidUrl(''), isNull);
      expect(firstValidUrl('ftp://files.example.com/x'), isNull);
      expect(firstValidUrl('see file:///etc/passwd'), isNull);
      expect(firstValidUrl('data:text/plain;base64,aGk='), isNull);
    });

    test('strips trailing sentence punctuation from the stored link', () {
      final cases = <String, String>{
        'https://example.com.': 'https://example.com',
        'https://example.com,': 'https://example.com',
        'https://example.com;': 'https://example.com',
        'https://example.com:': 'https://example.com',
        'https://example.com!': 'https://example.com',
        'https://example.com?': 'https://example.com',
        'https://example.com)': 'https://example.com',
        'https://example.com]': 'https://example.com',
        'https://example.com}': 'https://example.com',
        'https://example.com/path.': 'https://example.com/path',
        'https://example.com/path)': 'https://example.com/path',
      };
      cases.forEach((raw, expected) {
        final link = firstValidUrl('see $raw end');
        expect(link, isNotNull, reason: raw);
        expect(link!.url, expected, reason: raw);
        expect(link.raw, raw, reason: 'the raw text is never rewritten');
      });
    });

    test('keeps a legitimate trailing slash', () {
      final link = firstValidUrl('https://example.com/path/');
      expect(link!.url, 'https://example.com/path/');
    });

    test('containsWebUrl mirrors firstValidUrl', () {
      expect(containsWebUrl('go to https://example.com'), isTrue);
      expect(containsWebUrl('go to javascript:alert(1)'), isFalse);
    });

    test('percent-encodes a unicode host instead of rejecting it', () {
      // Documented behaviour: `Uri` percent-encodes the host, so an IDN-like
      // host is stored as a link in its encoded form. It never becomes a
      // non-http scheme, so the scheme allow-list still holds.
      final link = firstValidUrl('https://exämple.com/x');
      expect(link, isNotNull);
      expect(link!.url, 'https://ex%C3%A4mple.com/x');
      expect(link.raw, 'https://exämple.com/x');
    });
  });

  group('cleanInstagramUrl', () {
    test('strips the igsh tracking parameter', () {
      expect(
        cleanInstagramUrl('https://www.instagram.com/reel/ABC/?igsh=XYZ'),
        'https://www.instagram.com/reel/ABC/',
      );
    });

    test('strips the igshid tracking parameter', () {
      expect(
        cleanInstagramUrl('https://www.instagram.com/p/1/?igshid=abc'),
        'https://www.instagram.com/p/1/',
      );
    });

    test('keeps every other parameter (only igsh/igshid are tracking)', () {
      expect(
        cleanInstagramUrl(
          'https://www.instagram.com/reel/ABC/?igsh=XYZ&utm_source=ig_web_copy_link',
        ),
        'https://www.instagram.com/reel/ABC/?utm_source=ig_web_copy_link',
      );
      expect(
        cleanInstagramUrl('https://www.instagram.com/p/1/?si=abcdef'),
        'https://www.instagram.com/p/1/?si=abcdef',
      );
    });

    test('leaves non-Instagram hosts untouched', () {
      const url = 'https://example.com/?igsh=XYZ';
      expect(cleanInstagramUrl(url), url);
    });

    test('works on the instagram.com apex host too', () {
      expect(
        cleanInstagramUrl('https://instagram.com/p/1/?igsh=XYZ'),
        'https://instagram.com/p/1/',
      );
    });

    test('keeps the path and the fragment', () {
      expect(
        cleanInstagramUrl('https://www.instagram.com/reel/ABC/?igsh=XYZ#frag'),
        'https://www.instagram.com/reel/ABC/#frag',
      );
    });

    test('returns the input unchanged when there is nothing to strip', () {
      const url = 'https://www.instagram.com/reel/ABC/';
      expect(cleanInstagramUrl(url), url);
    });

    test('does not touch a look-alike host', () {
      const url = 'https://notinstagram.com/p/1/?igsh=XYZ';
      expect(cleanInstagramUrl(url), url);
    });
  });

  group('size limits', () {
    test('exposes the documented limits', () {
      expect(maxMessageBytes, 64 * 1024);
      expect(maxNoteBytes, 256 * 1024);
      expect(maxTitleChars, 200);
      expect(maxCategoryNameChars, 60);
    });

    test('rejects empty or blank message text', () {
      expect(isValidMessageText(''), isFalse);
      expect(isValidMessageText('   '), isFalse);
      expect(isValidMessageText('\n\t '), isFalse);
      expect(isValidMessageText('a'), isTrue);
    });

    test(
      'accepts a message of exactly the byte limit and rejects one byte more',
      () {
        expect(isValidMessageText('a' * maxMessageBytes), isTrue);
        expect(isValidMessageText('a' * (maxMessageBytes + 1)), isFalse);
      },
    );

    test('measures the message limit in UTF-8 bytes, not characters', () {
      // U+1F600 is 4 UTF-8 bytes.
      expect(isValidMessageText('\u{1F600}' * (maxMessageBytes ~/ 4)), isTrue);
      expect(
        isValidMessageText('\u{1F600}' * (maxMessageBytes ~/ 4 + 1)),
        isFalse,
      );
    });

    test(
      'accepts a note of exactly the byte limit and rejects one byte more',
      () {
        expect(isValidNoteText('a' * maxNoteBytes), isTrue);
        expect(isValidNoteText('a' * (maxNoteBytes + 1)), isFalse);
      },
    );

    test('validateMessageText throws instead of truncating', () {
      expect(() => validateMessageText(''), throwsA(isA<ValidationError>()));
      expect(() => validateMessageText('  '), throwsA(isA<ValidationError>()));
      expect(
        () => validateMessageText('a' * (maxMessageBytes + 1)),
        throwsA(isA<ValidationError>()),
      );
      expect(() => validateMessageText('hello'), returnsNormally);
    });

    test('validateNoteText throws instead of truncating', () {
      expect(
        () => validateNoteText('a' * (maxNoteBytes + 1)),
        throwsA(isA<ValidationError>()),
      );
      expect(() => validateNoteText('hello'), returnsNormally);
    });

    test('validates the title length', () {
      expect(isValidTitle(null), isTrue);
      expect(isValidTitle(''), isTrue);
      expect(isValidTitle('a' * maxTitleChars), isTrue);
      expect(isValidTitle('a' * (maxTitleChars + 1)), isFalse);
      expect(
        () => validateTitle('a' * (maxTitleChars + 1)),
        throwsA(isA<ValidationError>()),
      );
      expect(() => validateTitle('a' * maxTitleChars), returnsNormally);
    });

    test('never truncates: the rejected string is not shortened', () {
      final tooBig = 'a' * (maxMessageBytes + 1);
      Object? caught;
      try {
        validateMessageText(tooBig);
      } on Object catch (e) {
        caught = e;
      }
      expect(caught, isA<ValidationError>());
      expect(tooBig.length, maxMessageBytes + 1);
    });
  });

  group('unicode handling', () {
    test('keeps emoji, RTL text and combining marks intact', () {
      const text = 'مرحبا 👋🏽 é — 你好';
      expect(() => validateMessageText(text), returnsNormally);
      expect(utf8.encode(text).length, greaterThan(text.length));
    });

    test('accepts a zero-width joiner sequence', () {
      const text = '👨‍👩‍👧‍👦';
      expect(() => validateMessageText(text), returnsNormally);
    });

    test('decodeUtf8Strict rejects invalid byte sequences', () {
      expect(decodeUtf8Strict([0xff, 0xfe]), isNull);
      expect(decodeUtf8Strict([0xc3]), isNull);
      expect(decodeUtf8Strict(utf8.encode('ok')), 'ok');
    });

    test('isWellFormedUnicode rejects a lone surrogate', () {
      // `utf8.encode` replaces unpaired surrogates with U+FFFD instead of
      // throwing, so the guard inspects the code units directly. A remote row
      // carrying a lone surrogate must be rejected (SYNC-006), not silently
      // stored as U+FFFD.
      expect(isWellFormedUnicode('\uD800'), isFalse);
      expect(isWellFormedUnicode('\uDC00'), isFalse);
      expect(isWellFormedUnicode('a\uD800b'), isFalse);
      expect(isWellFormedUnicode('\uD800\uDC00'), isTrue);
      expect(isWellFormedUnicode('plain'), isTrue);
      expect(isWellFormedUnicode('👋🏽'), isTrue);
    });

    test('the content hash is stable for identical content', () {
      final a = contentHashOf(text: 'héllo 👋', title: 'T', url: null);
      final b = contentHashOf(text: 'héllo 👋', title: 'T', url: null);
      expect(a, b);
      expect(a.length, 64);
      final c = contentHashOf(
        text: 'héllo 👋',
        title: 'T',
        url: 'https://x.dev',
      );
      expect(c, isNot(a));
    });
  });

  group('category name rules', () {
    test('rejects an empty or whitespace-only name', () {
      expect(isValidCategoryName(''), isFalse);
      expect(isValidCategoryName('   '), isFalse);
      expect(isValidCategoryName('\t\n'), isFalse);
    });

    test('accepts a name of exactly 60 characters', () {
      expect(isValidCategoryName('a' * 60), isTrue);
      expect(isValidCategoryName('a' * 61), isFalse);
    });

    test('counts characters after trimming and collapsing whitespace', () {
      expect(isValidCategoryName('  ${'a' * 60}  '), isTrue);
      // 61 raw characters, but the collapsed name is 59 characters long.
      expect(isValidCategoryName('${'a' * 29}   ${'b' * 29}'), isTrue);
    });

    test('validateCategoryName throws for invalid names', () {
      expect(() => validateCategoryName(''), throwsA(isA<ValidationError>()));
      expect(
        () => validateCategoryName('a' * 61),
        throwsA(isA<ValidationError>()),
      );
      expect(() => validateCategoryName('ok'), returnsNormally);
    });

    test('normalizeCategoryName lower-cases and collapses whitespace', () {
      expect(normalizeCategoryName('  ReSearch   Notes '), 'research notes');
      expect(normalizeCategoryName('Inbox'), 'inbox');
    });
  });
}
