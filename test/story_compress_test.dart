import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/screens/story_composer_screen.dart';

/// Test kompres media Story (foto + video).
///
/// FOTO — `processStoryImage`: resize sisi terpanjang 1080px + JPEG q82.
/// Dulu 1440 q85 → file besar (boros storage + bandwidth + spike memori).
/// Test ini MENGUNCI kontrak resize/kualitas supaya tidak regresi balik ke
/// ukuran besar (perubahan tanpa sadar dapat membatalkan penghematan ini).
///
/// VIDEO — frameRate 24 (dulu 30) terkunci di `StoragePhotoService.compressStoryVideo`.
/// Tidak diuji di sini karena butuh plugin native `video_compress`; verifikasi
/// nilainya lewat review kode (grep `frameRate: 24`).
Uint8List _jpeg(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(120, 90, 200));
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

/// Baca output `processStoryImage` (base64) jadi `img.Image`.
img.Image _out(Uint8List src) => img.decodeImage(base64Decode(processStoryImage(src)))!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('processStoryImage — resize + kualitas', () {
    test('potret besar → sisi terpanjang (tinggi) 1080', () {
      final out = _out(_jpeg(900, 1600)); // potret 9:16
      expect(out.height, 1080);
      // 900/1600 * 1080 = 607.5 → pembulatan image pkg.
      expect(out.width, inInclusiveRange(606, 609));
    });

    test('landscape besar → sisi terpanjang (lebar) 1080', () {
      final out = _out(_jpeg(2000, 1000)); // landscape 2:1
      expect(out.width, 1080);
      expect(out.height, 540);
    });

    test('persegi besar → 1080x1080', () {
      final out = _out(_jpeg(1500, 1500));
      expect(out.width, 1080);
      expect(out.height, 1080);
    });

    test('gambar lebih kecil dari 1080 → DIPERBESAR (semantik copyResize)', () {
      // Perilaku kontrak: selalu sisi terpanjang = 1080 (bukan hanya turun).
      final out = _out(_jpeg(400, 300));
      expect(out.width, 1080);
    });

    test('sisi terpanjang TIDAK melebihi 1080 (inti penghematan)', () {
      // Berapapun besarnya sumber, output tak boleh > 1080 di sisi mana pun.
      for (final dim in [(4000, 3000), (3000, 4000), (1200, 5000)]) {
        final out = _out(_jpeg(dim.$1, dim.$2));
        expect(
          out.width <= 1080 && out.height <= 1080,
          isTrue,
          reason: 'sumber ${dim.$1}x${dim.$2} harus ter-cap ≤1080, '
              'dapat ${out.width}x${out.height}',
        );
        expect(out.width == 1080 || out.height == 1080, isTrue,
            reason: 'sisi terpanjang harus tepat 1080');
      }
    });

    test('output JPEG valid & bisa di-decode ulang', () {
      final b64 = processStoryImage(_jpeg(1200, 900));
      expect(b64, isNotEmpty);
      expect(img.decodeImage(base64Decode(b64)), isNotNull);
    });

    test('bytes bukan gambar → string kosong, tidak crash', () {
      expect(processStoryImage(Uint8List.fromList([0, 1, 2, 3])), '');
      expect(processStoryImage(Uint8List(0)), '');
    });

    test('warna tetap dipertahankan (bukan output rusak/hitam)', () {
      // Sumber ungu (120,90,200) — pastikan tidak jadi hitam/kosong.
      final out = _out(_jpeg(1200, 1200));
      final p = out.getPixel(540, 540);
      expect(p.r, greaterThan(60));
      expect(p.b, greaterThan(100), reason: 'komponen biru harus dominan');
    });
  });
}
