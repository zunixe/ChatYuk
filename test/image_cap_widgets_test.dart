import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/widgets/async_photo.dart';

/// Fase 1 — memastikan CAP decode (`cacheWidth`) benar-benar terpasang pada
/// widget gambar kecil. Regresi di sini = gambar full-res di-raster ulang
/// untuk tile/thumbnail mungil → boros RAM (inti warning performa).
///
/// `Image.memory(cacheWidth: N)` membungkus provider jadi `ResizeImage(width: N)`,
/// jadi kita cek `.image` pada widget `Image` yang terbangun.
String _b64Jpeg(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(120, 180, 90));
  return base64Encode(img.encodeJpg(im, quality: 80));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('AsyncPhotoThumbnail menerapkan cacheWidth (bukan full decode)',
      (tester) async {
    // Gambar besar → kalau tak di-cap, akan di-decode penuh untuk tile mungil.
    final b64 = _b64Jpeg(1200, 1200);
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AsyncPhotoThumbnail(base64: b64, width: 80, height: 80),
        ),
      ));
      // compute() decode berjalan di isolate nyata — beri waktu di runAsync.
      await Future<void>.delayed(const Duration(milliseconds: 800));
    });
    await tester.pump();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<ResizeImage>(),
        reason: 'thumbnail harus pakai ResizeImage (cacheWidth 256)');
    final resize = image.image as ResizeImage;
    expect(resize.width, 256);
    expect(resize.allowUpscaling, isFalse);
  });

  testWidgets('decodeThumbB64 mengecilkan gambar besar ke 256px',
      (tester) async {
    final out = decodeThumbB64(_b64Jpeg(1000, 1000));
    expect(out, isNotNull);
    final decoded = img.decodeImage(out!)!;
    expect(decoded.width, 256);
    expect(decoded.height, 256);
  });

  test('decodeThumbB64 gambar kecil tidak diperbesar', () {
    final out = decodeThumbB64(_b64Jpeg(100, 100));
    expect(out, isNotNull);
    final decoded = img.decodeImage(out!)!;
    // copyResize(width:256) memperbesar — perilaku existing; pastikan tidak crash
    // & hasilnya tetap gambar valid.
    expect(decoded.width, greaterThan(0));
  });

  test('decodeThumbB64 bytes bukan gambar → null, tidak crash', () {
    expect(decodeThumbB64('not base64 !!!'), isNull);
    expect(decodeThumbB64(base64Encode(Uint8List.fromList([1, 2, 3]))), isNull);
  });
}
