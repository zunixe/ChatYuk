import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/core/cache/photo_cache.dart';
import 'package:chatyuk/core/cache/post_photo_cache.dart';
import 'package:chatyuk/core/cache/media_disk_cache.dart';

/// Fase 2 — image/cache yang tadinya 0% coverage.
/// Logic-only: fungsi murni (thumbnail generator, LRU cap, hash nama file)
/// yang tidak butuh plugin native (Keystore/secure storage).
Uint8List _jpeg(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(80, 160, 200));
  return Uint8List.fromList(img.encodeJpg(im, quality: 80));
}

void main() {
  group('PhotoCache.genThumb — thumbnail chat 512px', () {
    test('base64 gambar besar → thumb 512px JPEG valid', () async {
      final b64 = base64Encode(_jpeg(1600, 1200));
      final out = await genThumb({'b64': b64});
      expect(out, isNotNull);
      final decoded = img.decodeImage(base64Decode(out!))!;
      expect(decoded.width, 512);
      expect(decoded.height, 384); // proporsional 4:3
    });

    test('bytes bukan gambar → null, tidak crash', () async {
      expect(await genThumb({'b64': 'xx'}), isNull);
      expect(
        await genThumb({'b64': base64Encode(Uint8List.fromList([9, 9, 9]))}),
        isNull,
      );
    });

    test('args tanpa key b64 → null (defensif)', () async {
      expect(await genThumb(<String, dynamic>{}), isNull);
    });
  });

  group('PhotoCache LRU cap', () {
    test('cap chat = 20MB, thumb = 8MB (kontrak memori)', () {
      expect(chatMemMaxChars, 20 * 1024 * 1024);
      expect(chatThumbMemMaxChars, 8 * 1024 * 1024);
    });

    test('chatMemShouldEvict: di batas → tidak, lewat → ya', () {
      expect(chatMemShouldEvict(100, 100), isFalse);
      expect(chatMemShouldEvict(101, 100), isTrue);
      expect(chatMemShouldEvict(50, 100), isFalse);
    });
  });

  group('PostPhotoCache.genPostThumb — thumbnail post 1024px', () {
    test('gambar besar → 1024px JPEG', () {
      final out = genPostThumb(_jpeg(3000, 2000));
      expect(out, isNotNull);
      final decoded = img.decodeImage(out!)!;
      expect(decoded.width, 1024);
      expect(decoded.height, 683); // ~3:2
    });

    test('gambar kecil → tetap berhasil (diperbesar ke 1024)', () {
      final out = genPostThumb(_jpeg(100, 100));
      expect(out, isNotNull);
      expect(img.decodeImage(out!)!.width, 1024);
    });

    test('bytes bukan gambar → null, tidak crash', () {
      expect(genPostThumb(Uint8List.fromList([0, 1, 2])), isNull);
      expect(genPostThumb(Uint8List(0)), isNull);
    });

    test('lruShouldEvict: di batas → tidak, lewat → ya', () {
      expect(lruShouldEvict(100, 100), isFalse);
      expect(lruShouldEvict(101, 100), isTrue);
    });

    test('cap memori post = 30MB', () {
      expect(postPhotoMemMaxBytes, 30 * 1024 * 1024);
    });
  });

  group('MediaDiskCache — hash nama file & kuota', () {
    test('mediaCacheFileName: deterministik (path sama → nama sama)', () {
      expect(
        mediaCacheFileName('avatars/uid/abc.jpg'),
        mediaCacheFileName('avatars/uid/abc.jpg'),
      );
    });

    test('mediaCacheFileName: path beda → nama beda (umumnya)', () {
      expect(
        mediaCacheFileName('avatars/a.jpg') ==
            mediaCacheFileName('avatars/b.jpg'),
        isFalse,
      );
    });

    test('mediaCacheFileName: format 8 digit hex', () {
      final n = mediaCacheFileName('posts/uid/123.jpg');
      expect(n.length, 8);
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(n), isTrue);
    });

    test('mediaCacheFileName: path kosong tetap valid', () {
      expect(mediaCacheFileName('').length, 8);
    });

    test('mediaCacheFileName: tidak tabrakan untuk 500 path mirip', () {
      final seen = <String>{};
      for (var i = 0; i < 500; i++) {
        seen.add(mediaCacheFileName('posts/uid_$i/photo_$i.jpg'));
      }
      // Sangat tinggi kemungkinan unik; toleransi bentrok hash minimal.
      expect(seen.length, greaterThan(495));
    });

    test('mediaQuotaExceeded: di batas → tidak, lewat → ya', () {
      expect(mediaQuotaExceeded(100, 0, 100), isFalse);
      expect(mediaQuotaExceeded(100, 1, 100), isTrue);
      expect(mediaQuotaExceeded(50, 50, 100), isFalse);
    });

    test('cap MediaDiskCache = 250MB', () {
      expect(MediaDiskCache.maxBytes, 250 * 1024 * 1024);
    });
  });
}
