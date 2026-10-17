import 'dart:typed_data';

import 'package:chatyuk/widgets/message/image_decode_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DecodedImage.safeDispose (R10)', () {
    test('idempoten — dipanggil 2x aman, disposed=true, image=null', () {
      final di = DecodedImage(Uint8List.fromList([1, 2, 3]), 10, 10);
      expect(di.disposed, isFalse);
      di.safeDispose();
      expect(di.disposed, isTrue);
      expect(di.image, isNull);
      // Kedua kali: tidak melempar.
      di.safeDispose();
      expect(di.disposed, isTrue);
    });

    test('attachDecodedImage tak memasang bitmap bila sudah disposed', () async {
      final di = DecodedImage(Uint8List.fromList([0xFF, 0xD8, 0xFF]), 1, 1);
      di.safeDispose();
      await attachDecodedImage(di);
      expect(di.image, isNull);
    });
  });

  group('decodedImageCache replace kunci-sama (R10)', () {
    test('isi sama (ukuran sama): objek lama yang TAMPIL dipertahankan, tak di-dispose', () {
      // Bubble yang sedang tampil memegang objek lama — men-dispose-nya
      // membuat bubble jatuh ke Image.memory async = kedip (log HP 2026-10-17).
      const key = 424242;
      final oldImg = DecodedImage(Uint8List.fromList([1]), 1, 1);
      final newImg = DecodedImage(Uint8List.fromList([2]), 1, 1);
      putDecodedCache(key, oldImg);
      putDecodedCache(key, newImg);
      expect(oldImg.disposed, isFalse);
      expect(newImg.disposed, isFalse);
      expect(identical(getDecodedCache(key), oldImg), isTrue);
    });

    test('ukuran beda (upgrade): diganti, objek lama TIDAK di-dispose paksa', () {
      const key = 424243;
      final oldImg = DecodedImage(Uint8List.fromList([1]), 100, 100);
      final newImg = DecodedImage(Uint8List.fromList([2]), 800, 800);
      putDecodedCache(key, oldImg);
      putDecodedCache(key, newImg);
      expect(oldImg.disposed, isFalse);
      expect(identical(getDecodedCache(key), newImg), isTrue);
    });

    test('objek lama yang sudah dilepas → diganti objek baru', () {
      const key = 424244;
      final oldImg = DecodedImage(Uint8List.fromList([1]), 1, 1);
      final newImg = DecodedImage(Uint8List.fromList([2]), 1, 1);
      putDecodedCache(key, oldImg);
      oldImg.safeDispose();
      putDecodedCache(key, newImg);
      expect(identical(getDecodedCache(key), newImg), isTrue);
    });

    test('put objek yang SAMA tidak men-dispose dirinya', () {
      const key = 777001;
      final img = DecodedImage(Uint8List.fromList([9]), 1, 1);
      putDecodedCache(key, img);
      putDecodedCache(key, img);
      expect(img.disposed, isFalse);
    });
  });
}
