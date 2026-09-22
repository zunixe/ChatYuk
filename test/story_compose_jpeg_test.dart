import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/screens/story_composer_screen.dart';

/// Fase 1 — `encodeRawRgbaToJpg`: konversi rawRgba (dari
/// ui.Image.toByteData(format: rawRgba)) → JPEG.
///
/// Menggantikan PNG encode lama (besar & lambat). Test ini mengunci:
/// - output JPEG valid & bisa di-decode
/// - dimensi tepat
/// - URUTAN CHANNEL tidak tertukar (R/B swap adalah bug klasik yang mudah
///   lolos kalau hanya cek "bytes valid")
Uint8List _solidRgba(int w, int h, int r, int g, int b, [int a = 255]) {
  final buf = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    buf[i * 4] = r;
    buf[i * 4 + 1] = g;
    buf[i * 4 + 2] = b;
    buf[i * 4 + 3] = a;
  }
  return buf;
}

void main() {
  group('encodeRawRgbaToJpg', () {
    test('output adalah JPEG valid yang bisa di-decode', () {
      final jpg = encodeRawRgbaToJpg(
        RawJpg(_solidRgba(4, 4, 10, 200, 30), 4, 4),
      );
      expect(jpg, isNotEmpty);
      expect(img.decodeImage(jpg), isNotNull);
    });

    test('dimensi output sama dengan input', () {
      final jpg = encodeRawRgbaToJpg(
        RawJpg(_solidRgba(16, 8, 100, 100, 100), 16, 8),
      );
      final out = img.decodeImage(jpg)!;
      expect(out.width, 16);
      expect(out.height, 8);
    });

    test('channel TIDAK tertukar — merah murni tetap merah', () {
      // RGBA: R=255 G=0 B=0. Kalau bug swap R/B, hasilnya jadi biru.
      final jpg = encodeRawRgbaToJpg(
        RawJpg(_solidRgba(8, 8, 255, 0, 0), 8, 8),
      );
      final p = img.decodeImage(jpg)!.getPixel(4, 4);
      expect(p.r, greaterThan(200), reason: 'R harus dominan');
      expect(p.b, lessThan(60), reason: 'B harus kecil (bukan swap)');
    });

    test('channel TIDAK tertukar — biru murni tetap biru', () {
      final jpg = encodeRawRgbaToJpg(
        RawJpg(_solidRgba(8, 8, 0, 0, 255), 8, 8),
      );
      final p = img.decodeImage(jpg)!.getPixel(4, 4);
      expect(p.b, greaterThan(200), reason: 'B harus dominan');
      expect(p.r, lessThan(60), reason: 'R harus kecil (bukan swap)');
    });

    test('hijau murni tetap hijau', () {
      final jpg = encodeRawRgbaToJpg(
        RawJpg(_solidRgba(8, 8, 0, 255, 0), 8, 8),
      );
      final p = img.decodeImage(jpg)!.getPixel(4, 4);
      expect(p.g, greaterThan(200));
    });

    test('putih tetap putih & hitam tetap hitam', () {
      final white = img.decodeImage(
        encodeRawRgbaToJpg(RawJpg(_solidRgba(4, 4, 255, 255, 255), 4, 4)),
      )!.getPixel(2, 2);
      expect(white.r, greaterThan(230));
      expect(white.g, greaterThan(230));
      expect(white.b, greaterThan(230));

      final black = img.decodeImage(
        encodeRawRgbaToJpg(RawJpg(_solidRgba(4, 4, 0, 0, 0), 4, 4)),
      )!.getPixel(2, 2);
      expect(black.r, lessThan(30));
      expect(black.g, lessThan(30));
      expect(black.b, lessThan(30));
    });

    test('pixel yang berbeda pada gambar tetap berbeda (bukan flat)', () {
      // Kiri merah, kanan hijau — pastikan posisi tetap terjaga setelah encode.
      final w = 8, h = 8;
      final buf = Uint8List(w * h * 4);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = (y * w + x) * 4;
          if (x < w ~/ 2) {
            buf[i] = 255; buf[i + 1] = 0; buf[i + 2] = 0;
          } else {
            buf[i] = 0; buf[i + 1] = 255; buf[i + 2] = 0;
          }
          buf[i + 3] = 255;
        }
      }
      final out = img.decodeImage(encodeRawRgbaToJpg(RawJpg(buf, w, h)))!;
      final left = out.getPixel(1, 4);
      final right = out.getPixel(6, 4);
      expect(left.r, greaterThan(left.g));
      expect(right.g, greaterThan(right.r));
    });
  });
}
