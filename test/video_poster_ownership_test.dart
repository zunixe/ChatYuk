import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/video_prefetch.dart';

import 'test_helper.dart';

/// OWNERSHIP & LIFECYCLE bitmap poster (Phase 8 "NATIVE IMAGE LIFECYCLE").
///
/// Mengunci aturan: pool `_posterImages` = pemilik; evict/clear = LEPAS
/// referensi (bukan dispose); replace kunci-sama = dispose milik sendiri;
/// decode ganda tak menumpuk; bubble hanya meminjam (tak dispose).
///
/// Catatan: `ui.Image` butuh engine Flutter — test ini fokus pada INVARIAN
/// yang bisa diverifikasi tanpa render (jumlah pool, tak crash, idempoten).
void main() {
  setUpAll(() async {
    await initSupabaseForTest();
    await prewarmMediaForTest();
  });

  // PNG 2×2 valid (dari base64) → decode ke ui.Image nyata.
  Uint8List tinyPng() => base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZ'
        'YAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
      );

  tearDown(() => VideoPrefetch.clearPosterMem());

  test('decode pertama → pool berisi 1, posterImageSync HIT', () async {
    final path = 'chat/c1/life1.mp4';
    expect(VideoPrefetch.hasPosterImage(path), isFalse);
    await VideoPrefetch.decodePosterFor(path, tinyPng());
    expect(VideoPrefetch.hasPosterImage(path), isTrue);
    expect(VideoPrefetch.posterImageSync(path), isNotNull);
  });

  test('decode ULANG kunci sama → tetap 1 (replace, tak menumpuk)', () async {
    final path = 'chat/c1/life2.mp4';
    await VideoPrefetch.decodePosterFor(path, tinyPng());
    final first = VideoPrefetch.posterImageSync(path);
    await VideoPrefetch.decodePosterFor(path, tinyPng());
    final second = VideoPrefetch.posterImageSync(path);
    // Entry tetap ada & tetap 1 (bukan 2).
    expect(VideoPrefetch.posterImageSync(path), isNotNull);
    // Decode kedua no-op (sudah ada) → instance SAMA (tak replace tanpa guna).
    expect(identical(first, second), isTrue,
        reason: 'kunci sama & sudah ada → tidak decode ulang');
  });

  test('dua decode BERSAMAAN kunci sama → tak dobel & tak crash', () async {
    final path = 'chat/c1/life3.mp4';
    await Future.wait([
      VideoPrefetch.decodePosterFor(path, tinyPng()),
      VideoPrefetch.decodePosterFor(path, tinyPng()),
      VideoPrefetch.decodePosterFor(path, tinyPng()),
    ]);
    expect(VideoPrefetch.hasPosterImage(path), isTrue);
    // Ambil handle → harus valid (bukan disposed).
    final img = VideoPrefetch.posterImageSync(path);
    expect(img, isNotNull);
    // clone() akan melempar bila handle sudah di-dispose → memastikan
    // image ini HIDUP (bukan use-after-dispose).
    final handle = img!.clone();
    handle.dispose();
  });

  test('pool DIBATASI — decode banyak path → jumlah tetap ≤ budget+1',
      () async {
    for (var i = 0; i < 40; i++) {
      await VideoPrefetch.decodePosterFor('chat/c1/many$i.mp4', tinyPng());
    }
    // Evict menjaga batas (budget 12); beri toleransi 1 (urutan evict).
    expect(VideoPrefetch.posterImageCount(), lessThanOrEqualTo(13),
        reason: 'evict harus menjaga pool tetap bounded (anti-leak)');
  });

  test('clearPosterMem → pool kosong, tak crash', () async {
    await VideoPrefetch.decodePosterFor('chat/c1/clr.mp4', tinyPng());
    expect(VideoPrefetch.posterImageCount(), greaterThan(0));
    VideoPrefetch.clearPosterMem();
    expect(VideoPrefetch.posterImageCount(), 0);
    expect(VideoPrefetch.posterImageSync('chat/c1/clr.mp4'), isNull);
  });

  test('decode bytes RUSAK → tidak crash, entry valid lain tetap ada',
      () async {
    final good = 'chat/c1/good.mp4';
    await VideoPrefetch.decodePosterFor(good, tinyPng());
    // Decode bytes bukan gambar → guard, tak crash, pool tak rusak.
    await VideoPrefetch.decodePosterFor(
      'chat/c1/bad.mp4',
      Uint8List.fromList([1, 2, 3, 4, 5]),
    );
    expect(VideoPrefetch.posterImageSync(good), isNotNull,
        reason: 'entry valid tidak boleh hilang karena decode gagal lain');
  });

  test('siklus mount/unmount berulang (clear+decode 50x) → tetap 1',
      () async {
    // Simulasi buka-tutup chat: clear (bubble unmount) lalu decode lagi.
    const path = 'chat/c1/cycle.mp4';
    for (var i = 0; i < 50; i++) {
      VideoPrefetch.clearPosterMem(); // lepas semua (bubble unmount)
      await VideoPrefetch.decodePosterFor(path, tinyPng());
    }
    expect(VideoPrefetch.posterImageCount(), 1);
    expect(VideoPrefetch.posterImageSync(path), isNotNull);
  });
}
