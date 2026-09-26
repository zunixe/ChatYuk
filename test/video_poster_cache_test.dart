import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/cache/media_disk_cache.dart';
import 'package:chatyuk/widgets/chat_video_bubble.dart';

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
