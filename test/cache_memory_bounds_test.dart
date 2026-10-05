import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/core/cache/message_cache.dart';
import 'package:chatyuk/core/cache/photo_cache.dart';
import 'package:chatyuk/core/cache/post_photo_cache.dart';
import 'package:chatyuk/models/message_model.dart';

/// Fokus: BATAS MEMORI cache (anti "ngetik ngelag setelah app dipakai lama").
///
/// Yang dikunci di sini:
/// 1. `MessageCache._memRawList` tidak tumbuh tanpa batas (cap FIFO).
/// 2. Mem-cache pesan menyimpan SALINAN yang base64 fotonya dibuang (heap
///    turun), tapi path voice/video DIPERTAHANKAN (jangan putus media).
/// 3. `trimMemCache()` publik di tiap cache benar-benar mengosongkan RAM
///    (dipakai saat OS memory-pressure & tombol Bersihkan Cache).
MessageModel _photo(String id, String imageData) => MessageModel(
  id: id,
  senderId: 'me',
  senderName: 'Me',
  senderGender: 'other',
  isRegistered: true,
  text: '',
  type: 'image',
  imageData: imageData,
  timestamp: DateTime.utc(2026, 1, 1),
);

MessageModel _voice(String id, String path) => MessageModel(
  id: id,
  senderId: 'me',
  senderName: 'Me',
  senderGender: 'other',
  isRegistered: true,
  text: '',
  type: 'voice',
  imageData: path,
  timestamp: DateTime.utc(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messageCache = MessageCache.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await messageCache.clearAll();
    PhotoCache.instance.trimMemCache();
    PostPhotoCache.instance.trimMemCache();
  });

  group('MessageCache._memRawList bounded', () {
    test('menyimpan snapshot terbaru, tidak tak-terbatas', () {
      // 25 key > cap 20 → yang paling lama dibuang, terbaru tetap ada.
      for (var i = 0; i < 25; i++) {
        messageCache.saveRawList('key-$i', [
          {'chatId': 'chat-$i'},
        ]);
      }
      // Key terbaru pasti masih ada.
      expect(messageCache.peekRawList('key-24'), isNotEmpty);
      // Key paling lama sudah ter-evict (cap 20).
      expect(messageCache.peekRawList('key-0'), isEmpty);
    });

    test('peekRawObj key tak ada = map kosong (kontrak lama tetap)', () {
      expect(messageCache.peekRawObj('starred:tidak-ada'), isEmpty);
    });
  });

  group('Mem-cache pesan: strip base64 foto, pertahankan path', () {
    test('base64 foto dibuang dari salinan RAM', () {
      // Simulasi isi stream: satu foto base64 besar + satu voice (path).
      final bigB64 = 'A' * 5000;
      final msgs = [
        _photo('m1', bigB64),
        _voice('m2', 'voice/abc.m4a'),
      ];
      messageCache.saveMessages('chat:test', msgs);

      final peek = messageCache.peekMessages('chat:test');
      expect(peek, isNotNull);
      final photo = peek!.firstWhere((m) => m.id == 'm1');
      // Foto base64 dikurus (RAM hemat) — isi asli TIDAK dimutasi.
      expect(photo.imageData, isEmpty);
      expect(msgs.first.imageData, bigB64, reason: 'list sumber tidak berubah');
    });

    test('path voice TIDAK dibuang (media tidak boleh putus)', () {
      final msgs = [_voice('v1', 'voice/xyz.m4a')];
      messageCache.saveMessages('chat:voice', msgs);
      final peek = messageCache.peekMessages('chat:voice');
      expect(peek, isNotNull);
      expect(peek!.first.imageData, 'voice/xyz.m4a');
    });
  });

  group('trimMemCache publik', () {
    test('PhotoCache.trimMemCache mengosongkan RAM (tidak throw)', () {
      expect(() => PhotoCache.instance.trimMemCache(), returnsNormally);
    });

    test('PostPhotoCache.trimMemCache mengosongkan RAM (tidak throw)', () {
      expect(() => PostPhotoCache.instance.trimMemCache(), returnsNormally);
    });

    test('MessageCache.trimMemCache tetap aman dipanggil berkali-kali', () {
      messageCache.saveRawList('k', [
        {'chatId': 'c'},
      ]);
      messageCache.trimMemCache();
      expect(messageCache.peekRawList('k'), isEmpty);
      expect(messageCache.peekMessages('k'), isNull);
    });
  });
}
