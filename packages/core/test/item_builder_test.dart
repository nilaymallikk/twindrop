import 'package:test/test.dart';
import 'package:twindrop_core/core.dart';

void main() {
  group('buildNewItem - messages', () {
    test('extracts the first http(s) URL from the text', () {
      final item = buildNewItem(
        type: ItemType.message,
        text: 'look at https://example.com/page and https://other.example',
        deviceId: 'device-a',
        deviceName: 'Device A',
        hlc: '000000000001000-00001-a',
        createdAt: 1000,
      );
      expect(item.url, 'https://example.com/page');
      expect(item.kind, ItemKind.link);
      expect(
        item.text,
        'look at https://example.com/page and https://other.example',
      );
    });

    test('keeps a non-web scheme as plain text', () {
      final item = buildNewItem(
        type: ItemType.message,
        text: 'javascript:alert(1)',
        deviceId: 'device-a',
        deviceName: 'Device A',
        hlc: '000000000001000-00001-a',
        createdAt: 1000,
      );
      expect(item.url, isNull);
      expect(item.kind, ItemKind.text);
    });

    test('cleans the Instagram tracking parameter but keeps the text', () {
      const text = 'https://www.instagram.com/reel/ABC/?igsh=XYZ';
      final item = buildNewItem(
        type: ItemType.message,
        text: text,
        deviceId: 'device-a',
        deviceName: 'Device A',
        hlc: '000000000001000-00001-a',
        createdAt: 1000,
      );
      expect(item.url, 'https://www.instagram.com/reel/ABC/');
      expect(item.text, text);
    });

    test('keeps the tracking parameter when clean_links is off', () {
      const text = 'https://www.instagram.com/reel/ABC/?igsh=XYZ';
      final item = buildNewItem(
        type: ItemType.message,
        text: text,
        deviceId: 'device-a',
        deviceName: 'Device A',
        hlc: '000000000001000-00001-a',
        createdAt: 1000,
        cleanInstagramLinks: false,
      );
      expect(item.url, text);
    });

    test('rejects an empty message', () {
      expect(
        () => buildNewItem(
          type: ItemType.message,
          text: '   ',
          deviceId: 'device-a',
          deviceName: 'Device A',
          hlc: '000000000001000-00001-a',
          createdAt: 1000,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an oversize message', () {
      expect(
        () => buildNewItem(
          type: ItemType.message,
          text: 'a' * (maxMessageBytes + 1),
          deviceId: 'device-a',
          deviceName: 'Device A',
          hlc: '000000000001000-00001-a',
          createdAt: 1000,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a message can never have a category', () {
      expect(
        () => buildNewItem(
          type: ItemType.message,
          text: 'hello',
          categoryId: 'inbox',
          deviceId: 'device-a',
          deviceName: 'Device A',
          hlc: '000000000001000-00001-a',
          createdAt: 1000,
        ),
        throwsA(isA<ValidationError>()),
      );
    });
  });

  group('buildNewItem - notes', () {
    test('rejects an empty note', () {
      expect(
        () => buildNewItem(
          type: ItemType.note,
          text: '  ',
          deviceId: 'device-a',
          deviceName: 'Device A',
          hlc: '000000000001000-00001-a',
          createdAt: 1000,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('rejects an explicit non-http URL', () {
      expect(
        () => buildNewItem(
          type: ItemType.note,
          text: 'hello',
          url: 'javascript:alert(1)',
          deviceId: 'device-a',
          deviceName: 'Device A',
          hlc: '000000000001000-00001-a',
          createdAt: 1000,
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('rejects an oversize title', () {
      expect(
        () => buildNewItem(
          type: ItemType.note,
          text: 'hello',
          title: 'a' * (maxTitleChars + 1),
          deviceId: 'device-a',
          deviceName: 'Device A',
          hlc: '000000000001000-00001-a',
          createdAt: 1000,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('the content hash covers text, title and url', () {
      final item = buildNewItem(
        type: ItemType.note,
        text: 'hello',
        title: 'Title',
        url: 'https://example.com',
        deviceId: 'device-a',
        deviceName: 'Device A',
        hlc: '000000000001000-00001-a',
        createdAt: 1000,
      );
      expect(
        item.contentHash,
        contentHashOf(
          text: 'hello',
          title: 'Title',
          url: 'https://example.com',
        ),
      );
      expect(item.prevHash, isNull);
      expect(item.deleted, isFalse);
      expect(item.pinned, isFalse);
      expect(item.isConflictCopy, isFalse);
    });
  });

  group('editedContent', () {
    Item base() => buildNewItem(
      type: ItemType.note,
      text: 'v1',
      title: 'Title',
      deviceId: 'device-a',
      deviceName: 'Device A',
      hlc: '000000000001000-00001-a',
      createdAt: 1000,
    );

    test('keeps the hash chain and updates the content hash', () {
      final current = base();
      final edited = editedContent(
        current,
        text: 'v2',
        hlc: '000000000002000-00001-a',
      );
      expect(edited.text, 'v2');
      expect(edited.prevHash, current.contentHash);
      expect(edited.contentHash, isNot(current.contentHash));
      expect(edited.title, 'Title');
    });

    test('rejects an empty note', () {
      expect(
        () => editedContent(
          base(),
          text: '   ',
          clearTitle: true,
          hlc: '000000000002000-00001-a',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('rejects a non-http URL', () {
      expect(
        () => editedContent(
          base(),
          url: 'javascript:alert(1)',
          hlc: '000000000002000-00001-a',
        ),
        throwsA(isA<ValidationError>()),
      );
    });

    test('picks up a link that the new text introduces', () {
      final edited = editedContent(
        base(),
        text: 'see https://example.com/new',
        hlc: '000000000002000-00001-a',
      );
      expect(edited.url, 'https://example.com/new');
      expect(edited.kind, ItemKind.link);
    });

    test('keeps the stored link when the new text has none', () {
      // Documented behaviour: the stored link is only re-extracted from the
      // text when the item has no link yet. Editing the text away from the
      // link keeps the previously validated http(s) URL.
      final withLink = buildNewItem(
        type: ItemType.note,
        text: 'see https://example.com/x',
        deviceId: 'device-a',
        deviceName: 'Device A',
        hlc: '000000000001000-00001-a',
        createdAt: 1000,
      );
      final edited = editedContent(
        withLink,
        text: 'no link any more',
        hlc: '000000000002000-00001-a',
      );
      expect(edited.url, 'https://example.com/x');
      expect(edited.text, 'no link any more');
    });

    test('drops the link when it is cleared explicitly', () {
      final withLink = buildNewItem(
        type: ItemType.note,
        text: 'see https://example.com/x',
        deviceId: 'device-a',
        deviceName: 'Device A',
        hlc: '000000000001000-00001-a',
        createdAt: 1000,
      );
      final edited = editedContent(
        withLink,
        text: 'see https://example.com/x',
        clearUrl: true,
        hlc: '000000000002000-00001-a',
      );
      expect(edited.url, isNull);
      expect(edited.kind, ItemKind.text);
    });
  });
}
