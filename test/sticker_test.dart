import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/services/sticker_fill.dart';
import 'package:chatyuk/services/storage_photo_service.dart';
import 'package:chatyuk/widgets/sticker_bubble.dart';

MessageModel _msg(
  String id, {
  String type = 'sticker',
  String imageData = '',
}) =>
    MessageModel(
      id: id,
      senderId: 'u1',
      senderName: 'U1',
      senderGender: 'other',
      isRegistered: true,
      text: '',
      type: type,
      imageData: imageData,
      timestamp: DateTime(2026, 1, 1),
    );

void main() {
  group('preserveStickerPaths', () {
    test('server kosong imageData → path lama dipertahankan', () {
      final old = [_msg('s1', imageData: 'stickers/u1/a.png')];
      // List server tak menyeleksi image_data → kosong.
      final fresh = [_msg('s1')];
      final out = preserveStickerPaths(fresh, old);
      expect(out.single.imageData, 'stickers/u1/a.png');
    });

    test('imageData server sudah terisi → tidak ditimpa', () {
      final old = [_msg('s1', imageData: 'stickers/u1/old.png')];
      final fresh = [_msg('s1', imageData: 'stickers/u1/new.png')];
      final out = preserveStickerPaths(fresh, old);
      expect(out.single.imageData, 'stickers/u1/new.png');
    });

    test('type berbeda id sama → TIDAK menyalin imageData', () {
      // Pesan ini dulu stiker, sekarang sudah jadi 'text' (mis. dihapus).
      final old = [_msg('s1', imageData: 'stickers/u1/a.png')];
      final fresh = [_msg('s1', type: 'text')];
      final out = preserveStickerPaths(fresh, old);
      expect(out.single.imageData, isEmpty);
    });

    test('id tak ada di old → dibiarkan kosong', () {
      final old = <MessageModel>[];
      final fresh = [_msg('s9')];
      final out = preserveStickerPaths(fresh, old);
      expect(out.single.imageData, isEmpty);
    });
  });

  group('stickerWidget (deteksi jenis)', () {
    test('bytes gzip (magic 1f 8b) + .tgs → Lottie', () {
      final gz = Uint8List.fromList([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0]);
      final w = stickerWidget(gz, 'stickers/u1/a.tgs', 100);
      expect(w.runtimeType.toString(), contains('Lottie'));
    });

    test('.mp4 → StickerVideo', () {
      final png = Uint8List.fromList([1, 2, 3, 4]);
      final w = stickerWidget(png, 'stickers/u1/a.mp4', 100);
      expect(w, isA<StickerVideo>());
    });

    test('.webm → StickerVideo', () {
      final png = Uint8List.fromList([1, 2, 3, 4]);
      final w = stickerWidget(png, 'stickers/u1/a.webm', 100);
      expect(w, isA<StickerVideo>());
    });

    test('.png biasa → Image (bukan video/lottie)', () {
      // Bytes PNG minimal (header) — Image.memory tak decode di build tree.
      final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0, 0, 0, 0]);
      final w = stickerWidget(png, 'stickers/u1/a.png', 100);
      expect(w, isNot(isA<StickerVideo>()));
      expect(w.runtimeType.toString(), contains('Image'));
    });
  });

  group('stickerExts (koleksi tidak kehilangan jenis)', () {
    test('mencakup png/webp/gif/tgs/mp4/mov/webm', () {
      for (final e in ['png', 'webp', 'gif', 'tgs', 'mp4', 'mov', 'webm']) {
        expect(
          StoragePhotoService.stickerExts.contains(e),
          isTrue,
          reason: 'ekstensi $e harus didukung koleksi',
        );
      }
    });

    test('ekstensi non-stiker (jpg/pdf) tidak termasuk', () {
      expect(StoragePhotoService.stickerExts.contains('jpg'), isFalse);
      expect(StoragePhotoService.stickerExts.contains('pdf'), isFalse);
    });
  });
}
