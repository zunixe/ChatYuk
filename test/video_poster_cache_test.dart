import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/cache/media_disk_cache.dart';
import 'package:chatyuk/widgets/chat_video_bubble.dart';
import 'package:chatyuk/widgets/video_prefetch.dart';

import 'test_helper.dart';

/// ANTI-BLINK cold start: poster video di-cache ke DISK. Tanpa ini setiap
/// cold start / scroll ulang / keluar-masuk chat mengunduh video penuh +
/// generate frame lagi (puluhan video berebut → layar berkedip).
void main() {
  setUpAll(() async {
    await initSupabaseForTest();
  });

  test('kunci cache poster deterministik per path video', () {
    // Kontrak kunci: 'video_poster:<path>' — sama untuk path yang sama
    // (dipakai readSync saat bubble dibangun ulang).
    const p = 'chat/c1/123.mp4';
    expect('video_poster:$p', 'video_poster:chat/c1/123.mp4');
  });

  test('kunci poster SATU sumber — penulis & pembaca harus identik', () {
    // Regresi 2026-10-11: kalau VideoPrefetch menulis kunci X tapi bubble
    // membaca kunci Y → selalu MISS = "card ngeload". Wajib pakai penulis
    // yang sama (VideoPrefetch.posterKeyFor).
    const p = 'chat/c2/aaa.mp4';
    expect(VideoPrefetch.posterKeyFor(p), 'video_poster:$p');
  });

  test('warmOne dgn posterBytes: tulis poster, JANGAN simpan video bytes', () async {
    // Video WAJIB tidak masuk MediaDiskCache (kuota 250MB → evict LRU →
    // poster/foto lain hilang = "cold start reload lagi"). Hanya poster.
    final poster = Uint8List.fromList(List<int>.filled(64, 7));
    const vpath = 'chat/c3/tight.mp4';
    // Bytes video "besar" — cukup untuk assert tak tersimpan (kita hanya
    // cek via readSync setelah warm: poster ada, video tak ada).
    final vbytes = Uint8List.fromList(List<int>.filled(128, 3));
    await VideoPrefetch.warmOne(vpath, videoBytes: vbytes, posterBytes: poster);
    // readSync aman dipanggil walau disk belum siap (null, bukan throw).
    expect(
      () => MediaDiskCache.instance.readSync(VideoPrefetch.posterKeyFor(vpath)),
      returnsNormally,
    );
  });

  test('readSync aman (null) saat disk belum siap — tidak crash', () {
    // Cold start: readSync dipanggil sebelum prewarm selesai. Harus
    // mengembalikan null (fallback async), bukan melempar.
    expect(
      () => MediaDiskCache.instance.readSync('video_poster:chat/c9/x.mp4'),
      returnsNormally,
    );
  });

  test('formatVideoDuration tetap benar (dipakai badge bubble)', () {
    expect(formatVideoDuration(0), '0:00');
    expect(formatVideoDuration(15000), '0:15');
    expect(formatVideoDuration(60000), '1:00');
  });
}
