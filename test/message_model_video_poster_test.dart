import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/message_model.dart';

/// Video chat: kolom `video_poster` (thumbnail dari pengirim) harus ikut
/// round-trip dari map server (snake + camel) dan cache, supaya PENERIMA +
/// cold-start menampilkan preview video (ala WhatsApp), bukan kotak hitam.
void main() {
  Map<String, dynamic> base() => {
        'id': '42',
        'senderId': 'u1',
        'senderName': 'Lawan',
        'senderGender': 'male',
        'isRegistered': true,
        'text': '',
        'type': 'video',
        'imageData': 'chat/c1/x.mp4',
        'timestamp': DateTime.utc(2026, 10, 11, 10).toIso8601String(),
        'durationMs': 7000,
      };

  group('MessageModel.videoPoster', () {
    test('baca snake_case dari server (video_poster)', () {
      final m = base()..['video_poster'] = 'chat/c1/x_poster.jpg';
      final msg = MessageModel.fromMap('42', m);
      expect(msg.videoPoster, 'chat/c1/x_poster.jpg');
    });

    test('baca camelCase dari cache (videoPoster)', () {
      final m = base()..['videoPoster'] = 'chat/c1/y_poster.jpg';
      final msg = MessageModel.fromMap('42', m);
      expect(msg.videoPoster, 'chat/c1/y_poster.jpg');
    });

    test('tanpa poster → string kosong (video lama)', () {
      final msg = MessageModel.fromMap('42', base());
      expect(msg.videoPoster, '');
    });

    test('pesan terhapus → poster dikosongkan (privasi)', () {
      final m = base()
        ..['isDeleted'] = true
        ..['video_poster'] = 'chat/c1/x_poster.jpg';
      final msg = MessageModel.fromMap('42', m);
      expect(msg.videoPoster, '');
    });

    test('toMap menyimpan videoPoster + round-trip', () {
      final m = base()..['video_poster'] = 'chat/c1/x_poster.jpg';
      final msg = MessageModel.fromMap('42', m);
      final back = MessageModel.fromMap('42', msg.toMap());
      expect(back.videoPoster, 'chat/c1/x_poster.jpg');
    });

    test('copyWith meneruskan videoPoster', () {
      final msg = MessageModel.fromMap('42', base());
      final next = msg.copyWith(imageData: 'chat/c1/x.mp4', videoPoster: 'chat/c1/z.jpg');
      expect(next.videoPoster, 'chat/c1/z.jpg');
    });
  });
}
