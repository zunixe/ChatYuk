import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/core/media/native_image.dart';
import 'package:chatyuk/core/media/chat_photo_helper.dart';

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
}
