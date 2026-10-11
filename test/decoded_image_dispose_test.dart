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
    test('objek lama untuk kunci sama di-dispose saat diganti', () {
      const key = 424242;
      final oldImg = DecodedImage(Uint8List.fromList([1]), 1, 1);
      final newImg = DecodedImage(Uint8List.fromList([2]), 1, 1);
      putDecodedCache(key, oldImg);
      expect(oldImg.disposed, isFalse);
      putDecodedCache(key, newImg);
      // Objek lama (digantikan) dilepas; objek baru tetap hidup.
      expect(oldImg.disposed, isTrue);
      expect(newImg.disposed, isFalse);
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
