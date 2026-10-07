import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/core/media/native_image.dart';

/// Test memori: kompres foto saat UPLOAD (avatar + post) & bukti bytes korup
/// tidak crash. Kini diproses di NATIVE (`NativeImage.processPost` /
/// `processSquare`; fallback Dart di chat_photo_helper).
///
/// Latar: perubahan Oktober 2026 mengecilkan ukuran upload —
/// - Post  : 1200 q82 → **1080 q78** (file ~30% lebih kecil)
/// - Avatar: 1024 q90 → **640 q85**  (file ~50% lebih kecil)
///
/// Bonus: bytes korup harus aman (return null) — dulu tanpa try/catch → crash
/// RangeError (ditemukan justru lewat test ini).
Uint8List _jpeg(int w, int h, [int r = 90, int g = 140, int b = 200]) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => NativeImage.resetAvailabilityForTest());

  group('NativeImage.processPost — foto post 1080px q78', () {
    test('lebar besar → di-resize ke 1080 (sisi acuan lebar)', () async {
      final out = (await NativeImage.processPost(_jpeg(3000, 2000)))!;
      expect(out.width, 1080);
      // 2000/3000 * 1080 = 720
      expect(out.height, 720);
      expect(img.decodeImage(out.bytes), isNotNull);
    });

    test('potret besar → lebar 1080, tinggi proporsional', () async {
      final out = (await NativeImage.processPost(_jpeg(1200, 2400)))!;
      expect(out.width, 1080);
      expect(out.height, 2160); // 2400/1200 * 1080
    });

    test('gambar kecil → DIPERBESAR ke lebar 1080 (semantik copyResize)', () async {
      final out = (await NativeImage.processPost(_jpeg(400, 300)))!;
      expect(out.width, 1080);
    });

    test('lebar hasil selalu tepat 1080 (kontrak ukuran)', () async {
      for (final dim in [(2000, 1500), (4000, 3000), (800, 600)]) {
        final out = (await NativeImage.processPost(_jpeg(dim.$1, dim.$2)))!;
        expect(out.width, 1080, reason: 'sumber ${dim.$1}x${dim.$2}');
      }
    });

    test('output JPEG valid & warna dipertahankan', () async {
      final out = (await NativeImage.processPost(_jpeg(1080, 1080, 200, 30, 40)))!;
      final p = img.decodeImage(out.bytes)!.getPixel(540, 540);
      expect(p.r, greaterThan(150), reason: 'anti corrupt/hitam');
    });

    test('bytes bukan gambar → null, tidak crash', () async {
      expect(await NativeImage.processPost(Uint8List.fromList([0, 1, 2, 3])), isNull);
      expect(await NativeImage.processPost(Uint8List(0)), isNull);
    });
  });

  group('NativeImage.processSquare — avatar 640px q85', () {
    test('kotak (crop 1:1) → 640x640', () async {
      final b64 = (await NativeImage.processSquare(_jpeg(1024, 1024), size: 640, quality: 85))!;
      final out = img.decodeImage(base64Decode(b64))!;
      expect(out.width, 640);
      expect(out.height, 640);
    });

    test('non-kotak → dipaksa 640x640 (crop area sudah 1:1 dari cropper)', () async {
      final b64 = (await NativeImage.processSquare(_jpeg(2000, 1200), size: 640, quality: 85))!;
      final out = img.decodeImage(base64Decode(b64))!;
      expect(out.width, 640);
      expect(out.height, 640);
    });

    test('>640px → TURUN ke 640 (inti penghematan)', () async {
      final b64 = (await NativeImage.processSquare(_jpeg(1600, 1600), size: 640, quality: 85))!;
      final out = img.decodeImage(base64Decode(b64))!;
      expect(out.width <= 640 && out.height <= 640, isTrue);
    });

    test('output JPEG valid & warna dipertahankan', () async {
      final b64 = (await NativeImage.processSquare(_jpeg(800, 800, 20, 180, 60), size: 640, quality: 85))!;
      final p = img.decodeImage(base64Decode(b64))!.getPixel(320, 320);
      expect(p.g, greaterThan(120), reason: 'hijau harus dominan');
    });

    test('bytes korup → null, TIDAK crash (regresi: dulu crash)', () async {
      expect(await NativeImage.processSquare(Uint8List.fromList([0, 1, 2, 3])), isNull);
      expect(await NativeImage.processSquare(Uint8List(0)), isNull);
      expect(await NativeImage.processSquare(Uint8List.fromList(List.filled(10, 7))), isNull);
    });
  });
}
