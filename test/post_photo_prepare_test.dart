import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/core/media/post_photo_prepare.dart';

/// Mengunci jalur upload FASE 2: fallback saat kompresi gagal, sumber dimensi,
/// dan BlurHash — tanpa ImagePicker/device.
void main() {
  Uint8List jpeg(int w, int h) =>
      Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

  test('sukses: pakai bytes+dimensi HASIL PROSES (bukan sumber)', () async {
    final raw = jpeg(4000, 3000);
    final processedBytes = Uint8List.fromList([9, 8, 7]);
    final out = await preparePostPhoto(
      raw,
      processor: (_) async =>
          (bytes: processedBytes, width: 1080, height: 810),
      blurhashOf: (_) async => 'HASH_OK',
    );
    expect(out, isNotNull);
    expect(out!.bytes, processedBytes, reason: 'yang diunggah = hasil proses');
    expect(out.w, 1080);
    expect(out.h, 810);
    expect(out.blurhash, 'HASH_OK');
  });

  test('kompresi GAGAL (null) → pakai FILE ASLI + dimensi dari header',
      () async {
    final raw = jpeg(100, 80);
    final out = await preparePostPhoto(
      raw,
      processor: (_) async => null,
      blurhashOf: (_) async => 'BH',
    );
    expect(out, isNotNull);
    expect(out!.bytes, same(raw), reason: 'jangan hilangkan foto user');
    expect(out.w, 100, reason: 'dimensi dari header file asli');
    expect(out.h, 80);
    expect(out.blurhash, 'BH', reason: 'metadata tetap dihitung');
  });

  test('kompresi MELEMPAR → tetap fallback file asli (tidak crash)', () async {
    final raw = jpeg(64, 48);
    final out = await preparePostPhoto(
      raw,
      processor: (_) async => throw StateError('boom'),
      blurhashOf: (_) async => '',
    );
    expect(out, isNotNull);
    expect(out!.bytes, same(raw));
    expect(out.w, 64);
    expect(out.h, 48);
  });

  test('bytes bukan gambar → null (pemanggil tampilkan error)', () async {
    final bad = Uint8List.fromList([1, 2, 3, 4]);
    final out = await preparePostPhoto(
      bad,
      processor: (_) async => null,
      blurhashOf: (_) async => 'x',
    );
    expect(out, isNull);
  });

  test('bytes kosong → null', () async {
    final out = await preparePostPhoto(
      Uint8List(0),
      processor: (_) async => null,
    );
    expect(out, isNull);
  });

  test('blurhash null (gagal) → string kosong, upload tetap jalan', () async {
    final raw = jpeg(32, 32);
    final out = await preparePostPhoto(
      raw,
      processor: (_) async => (bytes: raw, width: 32, height: 32),
      blurhashOf: (_) async => null,
    );
    expect(out, isNotNull);
    expect(out!.blurhash, '');
  });
}
