import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/core/media/native_image.dart';
import 'package:chatyuk/core/media/chat_photo_helper.dart';
import 'package:chatyuk/core/media/forensic_watermark.dart';

/// NativeImage: di environment test TANPA channel native, semua method harus
/// FALLBACK ke jalur Dart (`package:image`) dan tetap menghasilkan hasil benar.
/// (Channel native hanya ada di device — lihat android/.../ImageBridge.kt.)
Uint8List _jpeg(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(80, 160, 200));
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => NativeImage.resetAvailabilityForTest());

  test('isAvailable false tanpa channel native', () async {
    expect(await NativeImage.isAvailable(), isFalse);
  });

  test('aspectRatio fallback → dimensi benar', () async {
    final b64 = base64Encode(_jpeg(320, 200));
    final a = await NativeImage.aspectRatio(b64);
    expect(a, isNotNull);
    expect(a!.width, 320);
    expect(a.height, 200);
  });

  test('decodeBytes fallback → bytes utuh', () async {
    final src = _jpeg(120, 80);
    final out = await NativeImage.decodeBytes(base64Encode(src));
    expect(out, isNotNull);
    expect(out!.length, src.length);
  });

  test('decodeThumb fallback → JPEG diperkecil (sisi ≤ maxPx)', () async {
    final out = await NativeImage.decodeThumb(
      base64Encode(_jpeg(1000, 500)),
      maxPx: 256,
      quality: 80,
    );
    expect(out, isNotNull);
    final decoded = img.decodeImage(out!);
    expect(decoded, isNotNull);
    expect(decoded!.width, 256);
    expect(decoded.height, 128);
  });

  test('decodeWithDims fallback → bytes + dims', () async {
    final r = await NativeImage.decodeWithDims(base64Encode(_jpeg(400, 300)));
    expect(r, isNotNull);
    expect(r!.width, 400);
    expect(r.height, 300);
    expect(r.bytes, isNotEmpty);
  });

  test('processJpeg fallback → base64 JPEG diperkecil', () async {
    final out = await NativeImage.processJpeg(_jpeg(2000, 1000), maxPx: 800, quality: 75);
    expect(out, isNotNull);
    final decoded = img.decodeImage(base64Decode(out!));
    expect(decoded, isNotNull);
    expect(decoded!.width, 800);
    expect(decoded.height, 400);
  });

  test('input kosong → aman (null untuk yang tanpa foto)', () async {
    expect(await NativeImage.aspectRatio(''), isNull);
    expect(await NativeImage.decodeThumb(''), isNull);
    expect(await NativeImage.processJpeg(Uint8List(0)), isNull);
    // decodeBytes: paritas dengan base64Decode('') → bytes KOSONG (bukan null).
    final b = await NativeImage.decodeBytes('');
    expect(b, isNotNull);
    expect(b!.isEmpty, isTrue);
  });

  test('fallback helper dartDecodeThumbBytes/dartProcessJpegB64 konsisten', () {
    final t = dartDecodeThumbBytes((_jpeg(600, 300), 300, 80));
    expect(t, isNotNull);
    final d = img.decodeImage(t!);
    expect(d!.width, 300);

    final p = dartProcessJpegB64((_jpeg(1600, 800), 800, 75));
    expect(p, isNotNull);
    final d2 = img.decodeImage(base64Decode(p!));
    expect(d2!.width, 800);
  });

  test('processViewOnce fallback → JPEG base64, watermark terbaca seed benar',
      () async {
    // Foto uji bertekstur (gradien + noise halus) — sama pola dengan
    // forensic_watermark_test, terbukti menghasilkan sinyal DCT yang stabil.
    final im = img.Image(width: 1200, height: 1200);
    for (var y = 0; y < 1200; y++) {
      for (var x = 0; x < 1200; x++) {
        final r = (x * 255 ~/ 1200);
        final g = (y * 255 ~/ 1200);
        final b = ((x + y) * 255 ~/ 2400);
        final noise = ((x * 7 + y * 13) % 32) - 16;
        im.setPixelRgb(x, y, (r + noise).clamp(0, 255),
            (g + noise).clamp(0, 255), (b + noise).clamp(0, 255));
      }
    }
    final src = Uint8List.fromList(img.encodeJpg(im, quality: 92));

    final out = await NativeImage.processViewOnce(src, 'victim-uid-123');
    expect(out, isNotNull);

    final results = ForensicWatermark.detect(
      base64Decode(out!),
      const [
        'victim-uid-123',
        'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
      ],
    );
    expect(results, isNotEmpty);
    expect(results.first.seed, 'victim-uid-123');
    expect(results.first.matched, isTrue,
        reason: 'watermark native-fallback harus terbaca (z=${results.first.z})');
  });

  test('processViewOnce input kosong → null', () async {
    expect(await NativeImage.processViewOnce(Uint8List(0), 'seed'), isNull);
  });

  test('processPost fallback → lebar 1080, tinggi proporsional + dims', () async {
    final out = await NativeImage.processPost(_jpeg(3000, 2000));
    expect(out, isNotNull);
    expect(out!.width, 1080);
    expect(out.height, 720); // 2000/3000 * 1080
    final decoded = img.decodeImage(out.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 1080);
  });

  test('processPost potret → lebar 1080, tinggi proporsional', () async {
    final out = await NativeImage.processPost(_jpeg(1200, 2400));
    expect(out, isNotNull);
    expect(out!.width, 1080);
    expect(out.height, 2160); // 2400/1200 * 1080
  });

  test('processPost input kosong → null', () async {
    expect(await NativeImage.processPost(Uint8List(0)), isNull);
  });

  test('processStory fallback potret → tinggi 1080, base64 JPEG', () async {
    final out = await NativeImage.processStory(_jpeg(1200, 2400));
    expect(out, isNotNull);
    final decoded = img.decodeImage(base64Decode(out!));
    expect(decoded, isNotNull);
    expect(decoded!.height, 1080);
    expect(decoded.width, 540); // 1200/2400 * 1080
  });

  test('processStory fallback lanskap → lebar 1080', () async {
    final out = await NativeImage.processStory(_jpeg(2400, 1200));
    expect(out, isNotNull);
    final decoded = img.decodeImage(base64Decode(out!));
    expect(decoded!.width, 1080);
    expect(decoded.height, 540);
  });

  test('processStory input kosong → null', () async {
    expect(await NativeImage.processStory(Uint8List(0)), isNull);
  });

  test('processSquare fallback → 640x640 crop-stretch', () async {
    // Sumber non-persegi → hasil tetap 640x640 (crop-stretch).
    final out = await NativeImage.processSquare(_jpeg(900, 600));
    expect(out, isNotNull);
    final decoded = img.decodeImage(base64Decode(out!));
    expect(decoded, isNotNull);
    expect(decoded!.width, 640);
    expect(decoded.height, 640);
  });

  test('processSquare input kosong → null', () async {
    expect(await NativeImage.processSquare(Uint8List(0)), isNull);
  });

  test('processGalleryPhoto fallback → full 600 + preview 120 terblur',
      () async {
    final out = await NativeImage.processGalleryPhoto(_jpeg(1200, 900));
    expect(out, isNotNull);
    final full = img.decodeImage(base64Decode(out!.full));
    expect(full, isNotNull);
    expect(full!.width, 600);
    expect(full.height, 450); // 900/1200 * 600
    final prev = img.decodeImage(base64Decode(out.preview));
    expect(prev, isNotNull);
    expect(prev!.width, 120);
  });

  test('processGalleryPhoto input kosong → null', () async {
    expect(await NativeImage.processGalleryPhoto(Uint8List(0)), isNull);
  });

  test('processAdminThumb fallback → lebar maks 512', () async {
    final out = await NativeImage.processAdminThumb(base64Encode(_jpeg(1200, 800)));
    expect(out, isNotNull);
    final decoded = img.decodeImage(base64Decode(out!));
    expect(decoded, isNotNull);
    expect(decoded!.width, 512);
    expect(decoded.height, 341); // 800/1200 * 512
  });

  test('processAdminThumb kecil → tidak diperbesar', () async {
    final out = await NativeImage.processAdminThumb(base64Encode(_jpeg(300, 200)));
    final decoded = img.decodeImage(base64Decode(out!));
    expect(decoded!.width, 300);
  });

  test('processAdminThumb input kosong → null', () async {
    expect(await NativeImage.processAdminThumb(''), isNull);
  });

  test('aspectRatios fallback → rasio per gambar, null bila rusak', () async {
    final out = await NativeImage.aspectRatios([
      _jpeg(400, 200), // 2.0
      _jpeg(300, 300), // 1.0
      Uint8List.fromList([1, 2, 3]), // rusak → null
    ]);
    expect(out.length, 3);
    expect(out[0], closeTo(2.0, 0.001));
    expect(out[1], closeTo(1.0, 0.001));
    expect(out[2], isNull);
  });

  test('aspectRatios list kosong → kosong', () async {
    expect(await NativeImage.aspectRatios([]), isEmpty);
  });
}
