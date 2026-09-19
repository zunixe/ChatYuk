import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/core/media/chat_photo_helper.dart';
import 'package:chatyuk/core/media/forensic_watermark.dart';

/// Foto uji sintetis: pola gradien + blok warna (bukan noise murni) supaya
/// DCT punya konten realistis. Ukuran default 1200 (sama dengan embed).
Uint8List testJpeg({int w = 1200, int h = 1200}) {
  final im = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final r = (x * 255 / w).round();
      final g = (y * 255 / h).round();
      final b = ((x + y) * 255 / (w + h)).round();
      // Tekstur halus supaya variansi blok tidak nol.
      final noise = ((x * 7 + y * 13) % 32) - 16;
      im.setPixelRgb(
        x,
        y,
        (r + noise).clamp(0, 255),
        (g + noise).clamp(0, 255),
        (b + noise).clamp(0, 255),
      );
    }
  }
  return Uint8List.fromList(img.encodeJpg(im, quality: 92));
}

void main() {
  group('ForensicWatermark embed', () {
    test('embedToBase64 mengembalikan JPEG base64 yang bisa decode', () {
      final out = ForensicWatermark.embedToBase64(testJpeg(), 'victim-uid');
      expect(out, isNotNull);
      final bytes = base64Decode(out!);
      // Signature JPEG.
      expect(bytes[0], 0xFF);
      expect(bytes[1], 0xD8);
      expect(img.decodeImage(bytes), isNotNull);
    });

    test('embed mengecilkan gambar besar → sisi terpanjang <= size', () {
      final out = ForensicWatermark.embedToBase64(
        testJpeg(w: 2000, h: 1500),
        'victim-uid',
      );
      final decoded = img.decodeImage(base64Decode(out!))!;
      expect(decoded.width <= ForensicWatermark.size, isTrue);
      expect(decoded.height <= ForensicWatermark.size, isTrue);
    });

    test('gambar kecil dipertahankan ukurannya (tidak di-upscale)', () {
      final out = ForensicWatermark.embedToBase64(
        testJpeg(w: 400, h: 300),
        'victim-uid',
      );
      final decoded = img.decodeImage(base64Decode(out!))!;
      expect(decoded.width, 400);
      expect(decoded.height, 300);
    });

    test('bytes bukan gambar → null, tidak crash', () {
      // image 4.x melempar RangeError untuk bytes terlalu pendek —
      // embedToBase64 harus tetap mengembalikan null (bukan crash).
      expect(
        () => ForensicWatermark.embedToBase64(
          Uint8List.fromList([1, 2, 3, 4]),
          'seed',
        ),
        returnsNormally,
      );
      expect(
        ForensicWatermark.embedToBase64(Uint8List.fromList([1, 2, 3, 4]), 'seed'),
        isNull,
      );
    });
  });

  group('ForensicWatermark detect (roundtrip)', () {
    test('seed benar terdeteksi matched, seed lain tidak', () {
      const victim = 'victim-uid-123';
      final embedded = ForensicWatermark.embedToBase64(testJpeg(), victim)!;

      final results = ForensicWatermark.detect(
        base64Decode(embedded),
        const [
          victim,
          'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k',
        ],
      );

      expect(results, isNotEmpty);
      // Hasil diurut menurun berdasarkan rho → seed benar paling atas.
      expect(results.first.seed, victim);
      expect(results.first.matched, isTrue,
          reason: 'seed korban harus jadi outlier antar-seed');
      // Seed salah tidak boleh matched.
      for (final r in results.where((r) => r.seed != victim)) {
        expect(r.matched, isFalse);
      }
    });

    test('detect pada gambar TANPA watermark → tidak ada yang matched', () {
      final plain = testJpeg();
      final results = ForensicWatermark.detect(
        plain,
        const ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k'],
      );
      // Foto bersih tidak boleh memunculkan verdict positif.
      expect(results.any((r) => r.matched), isFalse);
    });

    test('detect gambar rusak → list kosong (tanpa crash)', () {
      expect(
        () => ForensicWatermark.detect(Uint8List.fromList([9, 9, 9]), const ['a', 'b']),
        returnsNormally,
      );
      expect(
        ForensicWatermark.detect(Uint8List.fromList([9, 9, 9]), const ['a', 'b']),
        isEmpty,
      );
    });
  });

  group('processChatPhoto (resize 1200, q82)', () {
    test('foto besar di-resize proporsional maks 1200', () {
      final out = processChatPhoto(testJpeg(w: 2400, h: 1200));
      expect(out, isNotNull);
      final decoded = img.decodeImage(base64Decode(out!))!;
      expect(decoded.width, 1200);
      expect(decoded.height, 600);
    });

    test('foto kecil tidak diperbesar', () {
      final out = processChatPhoto(testJpeg(w: 300, h: 200));
      final decoded = img.decodeImage(base64Decode(out!))!;
      expect(decoded.width, 300);
      expect(decoded.height, 200);
    });

    test('bytes bukan gambar → null, tidak crash', () {
      expect(() => processChatPhoto(Uint8List.fromList([0, 1])), returnsNormally);
      expect(processChatPhoto(Uint8List.fromList([0, 1])), isNull);
    });
  });

  group('processChatImage (resize 800, q75)', () {
    test('foto besar di-resize proporsional maks 800', () {
      final out = processChatImage(testJpeg(w: 1000, h: 2000));
      final decoded = img.decodeImage(base64Decode(out!))!;
      expect(decoded.height, 800);
      expect(decoded.width, 400);
    });

    test('foto kecil tidak diperbesar', () {
      final out = processChatImage(testJpeg(w: 500, h: 500));
      final decoded = img.decodeImage(base64Decode(out!))!;
      expect(decoded.width, 500);
      expect(decoded.height, 500);
    });

    test('bytes bukan gambar → null, tidak crash', () {
      expect(() => processChatImage(Uint8List.fromList([7])), returnsNormally);
      expect(processChatImage(Uint8List.fromList([7])), isNull);
    });
  });

  group('processViewOnceImage', () {
    test('menyematkan watermark seed penerima (roundtrip detect)', () {
      const viewer = 'viewer-uid-999';
      final out = processViewOnceImage((testJpeg(), viewer));
      expect(out, isNotNull);

      final results = ForensicWatermark.detect(
        base64Decode(out!),
        const [
          viewer,
          'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k',
        ],
      );
      expect(results.first.seed, viewer);
      expect(results.first.matched, isTrue);
    });
  });
}
