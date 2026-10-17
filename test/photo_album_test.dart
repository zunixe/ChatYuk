import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/widgets/date_chip.dart';

MessageModel _photo(String id, {String? albumId, String text = ''}) =>
    MessageModel(
      id: id,
      senderId: 'u1',
      senderName: 'A',
      senderGender: 'male',
      isRegistered: true,
      text: text,
      type: 'image',
      imageData: 'x',
      timestamp: DateTime(2026, 10, 18, 12),
      albumId: albumId,
    );

MessageModel _text(String id) => MessageModel(
  id: id,
  senderId: 'u1',
  senderName: 'A',
  senderGender: 'male',
  isRegistered: true,
  text: 'hi',
  type: 'text',
  imageData: '',
  timestamp: DateTime(2026, 10, 18, 12),
);

/// Cermin logika pengelompokan `_deriveItems` (album berurutan → 1 item).
List<ChatItem> groupAlbums(List<MessageModel> all) {
  final items = <ChatItem>[];
  final buf = <MessageModel>[];
  String? key;
  void flush() {
    if (buf.isEmpty) return;
    items.add(
      buf.length == 1
          ? ChatItem.message(buf.first)
          : ChatItem.album(List.of(buf)),
    );
    buf.clear();
    key = null;
  }

  for (final m in all) {
    final aid = m.albumId;
    if (aid != null && aid.isNotEmpty && m.type == 'image' && !m.isDeleted) {
      if (key != null && key != aid) flush();
      key = aid;
      buf.add(m);
      continue;
    }
    flush();
    items.add(ChatItem.message(m));
  }
  flush();
  return items;
}

void main() {
  group('album grouping', () {
    test('3 foto albumId sama -> 1 item album', () {
      final items = groupAlbums([
        _photo('a', albumId: 'X'),
        _photo('b', albumId: 'X'),
        _photo('c', albumId: 'X'),
      ]);
      expect(items.length, 1);
      expect(items.single.isAlbum, isTrue);
      expect(items.single.album.length, 3);
    });

    test('tanpa albumId -> perilaku lama (item per pesan)', () {
      final items = groupAlbums([_photo('a'), _photo('b')]);
      expect(items.length, 2);
      expect(items.any((e) => e.isAlbum), isFalse);
    });

    test('album 1 foto -> bukan album (bubble biasa)', () {
      final items = groupAlbums([_photo('a', albumId: 'X')]);
      expect(items.length, 1);
      expect(items.single.isAlbum, isFalse);
      expect(items.single.msg?.id, 'a');
    });

    test('albumId berbeda berselang -> dua album terpisah', () {
      final items = groupAlbums([
        _photo('a', albumId: 'X'),
        _photo('b', albumId: 'X'),
        _photo('c', albumId: 'Y'),
        _photo('d', albumId: 'Y'),
      ]);
      expect(items.length, 2);
      expect(items[0].album.map((e) => e.id), ['a', 'b']);
      expect(items[1].album.map((e) => e.id), ['c', 'd']);
    });

    test('pesan teks memutus album', () {
      final items = groupAlbums([
        _photo('a', albumId: 'X'),
        _text('t'),
        _photo('b', albumId: 'X'),
      ]);
      expect(items.length, 3);
      expect(items[0].isAlbum, isFalse);
      expect(items[1].isAlbum, isFalse);
      expect(items[2].isAlbum, isFalse);
    });

    test('pesan terhapus tidak dianggap anggota album', () {
      final deleted = MessageModel(
        id: 'd',
        senderId: 'u1',
        senderName: 'A',
        senderGender: 'male',
        isRegistered: true,
        text: '',
        type: 'text',
        imageData: '',
        timestamp: DateTime(2026, 10, 18, 12),
        isDeleted: true,
        albumId: 'X',
      );
      final items = groupAlbums([
        _photo('a', albumId: 'X'),
        deleted,
        _photo('b', albumId: 'X'),
      ]);
      expect(items.length, 3);
    });
  });

  group('ChatItem.album', () {
    test('primary = foto pertama; isAlbum true', () {
      final it = ChatItem.album([_photo('a', albumId: 'X'), _photo('b', albumId: 'X')]);
      expect(it.isAlbum, isTrue);
      expect(it.primary?.id, 'a');
      expect(it.msg, isNull);
      expect(it.dateLabel, isNull);
    });

    test('caption disimpan di foto terakhir (dipakai renderer)', () {
      final it = ChatItem.album([
        _photo('a', albumId: 'X'),
        _photo('b', albumId: 'X', text: 'liburan'),
      ]);
      expect(it.album.last.text, 'liburan');
    });
  });
}
