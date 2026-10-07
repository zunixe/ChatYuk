import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/core/media/native_image.dart';

/// Test kompres media Story (foto + video).
///
/// FOTO — `NativeImage.processStory`: resize sisi terpanjang 1080px + JPEG q82
/// (kini di NATIVE, fallback Dart di chat_photo_helper). Dulu 1440 q85 → file
/// besar (boros storage + bandwidth + spike memori). Test ini MENGUNCI kontrak
/// resize/kualitas supaya tidak regresi balik ke ukuran besar.
///
/// VIDEO — frameRate 24 terkunci di `StoragePhotoService.compressStoryVideo`
/// (butuh plugin native `video_compress`; verifikasi lewat grep).
Uint8List _jpeg(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(120, 90, 200));
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

Future<img.Image> _out(Uint8List src) async =>
    img.decodeImage(base64Decode((await NativeImage.processStory(src))!))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => NativeImage.resetAvailabilityForTest());

  group('NativeImage.processStory — resize + kualitas', () {
    test('potret besar → sisi terpanjang (tinggi) 1080', () async {
      final out = await _out(_jpeg(900, 1600)); // potret 9:16
      expect(out.height, 1080);
      expect(out.width, inInclusiveRange(606, 609));
    });

    test('landscape besar → sisi terpanjang (lebar) 1080', () async {
      final out = await _out(_jpeg(2000, 1000)); // landscape 2:1
      expect(out.width, 1080);
      expect(out.height, 540);
    });

    test('persegi besar → 1080x1080', () async {
      final out = await _out(_jpeg(1500, 1500));
      expect(out.width, 1080);
      expect(out.height, 1080);
    });

    test('gambar lebih kecil dari 1080 → DIPERBESAR (semantik copyResize)', () async {
      final out = await _out(_jpeg(400, 300));
      expect(out.width, 1080);
    });

    test('sisi terpanjang TIDAK melebihi 1080 (inti penghematan)', () async {
      for (final dim in [(4000, 3000), (3000, 4000), (1200, 5000)]) {
        final out = await _out(_jpeg(dim.$1, dim.$2));
        expect(
          out.width <= 1080 && out.height <= 1080,
          isTrue,
          reason: 'sumber ${dim.$1}x${dim.$2} harus ter-cap ≤1080',
        );
        expect(out.width == 1080 || out.height == 1080, isTrue,
            reason: 'sisi terpanjang harus tepat 1080');
      }
    });

    test('output JPEG valid & bisa di-decode ulang', () async {
      final b64 = await NativeImage.processStory(_jpeg(1200, 900));
      expect(b64, isNotNull);
      expect(b64!, isNotEmpty);
      expect(img.decodeImage(base64Decode(b64)), isNotNull);
    });

    test('bytes bukan gambar → null, tidak crash', () async {
      expect(await NativeImage.processStory(Uint8List.fromList([0, 1, 2, 3])), isNull);
      expect(await NativeImage.processStory(Uint8List(0)), isNull);
    });

    test('warna tetap dipertahankan (bukan output rusak/hitam)', () async {
      final out = await _out(_jpeg(1200, 1200));
      final p = out.getPixel(540, 540);
      expect(p.r, greaterThan(60));
      expect(p.b, greaterThan(100), reason: 'komponen biru harus dominan');
    });
  });
}
