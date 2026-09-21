import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/models/room_model.dart';
import 'package:chatyuk/models/story_model.dart';
import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/services/chat_service.dart' show PrivateChatInfo;

MessageModel _msg({
  String id = 'm1',
  String text = 'halo',
  String type = 'text',
  String imageData = '',
  bool isDeleted = false,
}) => MessageModel(
  id: id,
  senderId: 'u1',
  senderName: 'Andi',
  senderGender: 'male',
  isRegistered: true,
  text: text,
  type: type,
  imageData: imageData,
  timestamp: DateTime.utc(2026, 1, 2, 3, 4, 5),
  isDeleted: isDeleted,
);

void main() {
  group('MessageModel privasi hapus', () {
    test('fromMap pesan terhapus mengosongkan teks & media', () {
      final m = MessageModel.fromMap('m1', {
        'senderId': 'u1',
        'text': 'rahasia',
        'type': 'image',
        'imageData': 'base64data',
        'isDeleted': true,
      });
      expect(m.isDeleted, isTrue);
      expect(m.text, isEmpty);
      expect(m.imageData, isEmpty);
      expect(m.type, 'text');
    });

    test('toMap pesan terhapus tidak membawa isi ke cache', () {
      final map = _msg(
        text: 'rahasia',
        imageData: 'b64',
        isDeleted: true,
      ).toMap();
      expect(map['text'], isEmpty);
      expect(map['imageData'], isEmpty);
      expect(map['type'], 'text');
      expect(map['isDeleted'], isTrue);
    });

    test('copyWith(isDeleted: true) mengosongkan konten di memori', () {
      final m = _msg(
        text: 'rahasia',
        imageData: 'b64',
      ).copyWith(isDeleted: true);
      expect(m.isDeleted, isTrue);
      expect(m.text, isEmpty);
      expect(m.imageData, isEmpty);
    });

    test('roundtrip normal mempertahankan isi', () {
      final m = _msg(text: 'halo dunia', imageData: 'b64');
      final back = MessageModel.fromMap('m1', m.toMap());
      expect(back.text, 'halo dunia');
      expect(back.imageData, 'b64');
      expect(back.isDeleted, isFalse);
    });

    test('fromMap id int server dipakai, fallback argumen bila kosong', () {
      expect(MessageModel.fromMap('arg', {'id': 123}).id, '123');
      expect(MessageModel.fromMap('arg', {}).id, 'arg');
    });

    test('imageData pilih voicePath/imagePath bila imageData kosong', () {
      final m = MessageModel.fromMap('m1', {
        'type': 'voice',
        'voice_path': '/v/1.m4a',
      });
      expect(m.imageData, '/v/1.m4a');
    });

    test('durationMs parse dari 3 varian key', () {
      expect(MessageModel.fromMap('m', {'durationMs': 1500}).durationMs, 1500);
      expect(MessageModel.fromMap('m', {'duration_ms': 1500}).durationMs, 1500);
      expect(MessageModel.fromMap('m', {}).durationMs, isNull);
    });
  });

  group('UserModel', () {
    test('fromMap default aman untuk map kosong', () {
      final u = UserModel.fromMap('u1', {});
      expect(u.uid, 'u1');
      expect(u.nickname, 'Anon');
      expect(u.gender, 'male');
      expect(u.points, 50);
      expect(u.hashtags, isEmpty);
      expect(u.isRegistered, isFalse);
    });

    test('status fallback dari flag online lawas', () {
      final u = UserModel.fromMap('u1', {'online': true});
      expect(u.status, 'online');
    });

    test('about default kosong + terbaca dari map', () {
      expect(UserModel.fromMap('u1', {}).about, '');
      expect(
        UserModel.fromMap('u1', {'about': 'Halo, saya Budi'}).about,
        'Halo, saya Budi',
      );
    });

    test('copyWith about tidak menghapus nilai lain', () {
      final u = UserModel.fromMap('u1', {'nickname': 'Budi', 'about': 'lama'});
      final updated = u.copyWith(about: 'baru');
      expect(updated.about, 'baru');
      expect(updated.nickname, 'Budi');
    });
  });

  group('RoomModel', () {
    test('fromMap default + snake_case server', () {
      final r = RoomModel.fromMap('r1', {
        'name': 'Curhat',
        'is_private': true,
        'owner_id': 'u9',
        'has_password': true,
      });
      expect(r.id, 'r1');
      expect(r.isPrivate, isTrue);
      expect(r.ownerId, 'u9');
      expect(r.hasPassword, isTrue);
      expect(r.icon, '💬');
      expect(r.expiresAt, isNull);
    });
  });

  group('StorySlide', () {
    test('visibility default registered bila tidak ada', () {
      final s = StorySlide.fromMap('s1', {'image_path': '/a.jpg'});
      expect(s.visibility, 'registered');
      expect(
        StorySlide.fromMap('s1', {'visibility': 'friends'}).visibility,
        'friends',
      );
    });
  });

  group('PrivateChatInfo', () {
    PrivateChatInfo info() => PrivateChatInfo(
      chatId: 'c1',
      participants: const ['u1', 'u2'],
      participantNames: const {'u1': 'A', 'u2': 'B'},
      lastMessage: 'hi',
      lastMessageAt: DateTime.utc(2026, 1, 1),
      unreadCounts: const {'u1': 3},
      pinnedBy: const ['u1'],
      mutedBy: const ['u2'],
      archivedBy: const [],
    );

    test('helper pin/mute/archive per uid', () {
      final c = info();
      expect(c.isPinnedFor('u1'), isTrue);
      expect(c.isPinnedFor('u2'), isFalse);
      expect(c.isMutedFor('u2'), isTrue);
      expect(c.isMutedFor('u1'), isFalse);
      expect(c.isArchivedFor('u1'), isFalse);
    });

    test('toMap/fromMap roundtrip mempertahankan state', () {
      final back = PrivateChatInfo.fromMap(info().toMap());
      expect(back.chatId, 'c1');
      expect(back.unreadCounts['u1'], 3);
      expect(back.isPinnedFor('u1'), isTrue);
      expect(back.isMutedFor('u2'), isTrue);
    });
  });
}
