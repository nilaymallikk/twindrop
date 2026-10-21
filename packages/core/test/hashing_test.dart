import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';

void main() {
  group('sha256Hex', () {
    test('matches the known vector for "abc"', () {
      expect(
        sha256Hex('abc'.codeUnits),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('hashes empty input', () {
      expect(
        sha256Hex(const <int>[]),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
    });
  });

  group('contentHashOf', () {
    test('is stable for identical content', () {
      final a = contentHashOf(text: 'hello', title: 'T', url: 'https://x.dev');
      final b = contentHashOf(text: 'hello', title: 'T', url: 'https://x.dev');
      expect(a, b);
      expect(a.length, 64);
    });

    test('changes when any field changes', () {
      final base = contentHashOf(text: 'hello', title: null, url: null);
      expect(
        contentHashOf(text: 'hello!', title: null, url: null),
        isNot(base),
      );
      expect(contentHashOf(text: 'hello', title: 'T', url: null), isNot(base));
      expect(
        contentHashOf(text: 'hello', title: null, url: 'https://x.dev'),
        isNot(base),
      );
    });

    test('the fields cannot be confused with each other', () {
      // "a\u0000b" must not hash like {"text": "a", "title": "b"}.
      final a = contentHashOf(text: 'a', title: 'b', url: null);
      final b = contentHashOf(text: 'a\u0000b', title: null, url: null);
      expect(a, isNot(b));
    });
  });

  group('token hashing', () {
    test('is the sha256 hex of the token', () {
      expect(tokenHashOf('abc'), sha256Hex('abc'.codeUnits));
      expect(tokenHashOf('abc').length, 64);
    });

    test('different tokens hash differently', () {
      expect(tokenHashOf('a'), isNot(tokenHashOf('b')));
    });
  });

  group('conflict copy id', () {
    test('is deterministic', () {
      final a = conflictCopyIdFor('item-1', 'hash-1');
      final b = conflictCopyIdFor('item-1', 'hash-1');
      expect(a, b);
      expect(a.length, 36);
      expect(a, a.toLowerCase());
    });

    test('differs for a different item or a different loser hash', () {
      expect(
        conflictCopyIdFor('item-1', 'hash-1'),
        isNot(conflictCopyIdFor('item-2', 'hash-1')),
      );
      expect(
        conflictCopyIdFor('item-1', 'hash-1'),
        isNot(conflictCopyIdFor('item-1', 'hash-2')),
      );
    });

    test('is the uuidv5 of the fixed namespace', () {
      expect(
        conflictCopyIdFor('item-1', 'hash-1'),
        deterministicId(conflictCopyNamespace, 'item-1:hash-1'),
      );
      expect(
        conflictCopyNamespace,
        '0f8fad5b-d9cb-469f-a165-70867728950e',
        reason: 'the namespace is fixed forever (SYNC-005)',
      );
    });
  });

  group('fingerprints', () {
    test('shortFingerprint is six uppercase hex characters', () {
      expect(shortFingerprint('abcdef0123456789'), 'ABCDEF');
      expect(shortFingerprint('ABCDEF0123456789'), 'ABCDEF');
      expect(shortFingerprint('ab-cd ef_0123'), 'ABCDEF');
    });

    test('shortFingerprint rejects a too-short pin', () {
      expect(() => shortFingerprint('abc'), throwsFormatException);
    });

    test('fingerprintHint is the first eight hex characters', () {
      expect(fingerprintHint('abcdef0123456789'), 'abcdef01');
    });
  });

  group('ids', () {
    test('newId returns a lowercase UUIDv7', () {
      final id = newId();
      expect(
        id,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(id, isNot(newId()));
    });

    test('newId is time ordered', () async {
      final first = newId();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = newId();
      expect(second.compareTo(first), greaterThan(0));
    });
  });
}
