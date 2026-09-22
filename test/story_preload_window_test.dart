import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/screens/story_viewer_screen.dart';

/// Fase 1 — kontrak windowed preload story.
///
/// `_preloadWindow` di viewer sengaja memuat slide [aktif-1 .. aktif+ahead]
/// saja (bukan SEMUA slide) supaya byte slide (~5MB tiap) tidak menumpuk di
/// RAM. Logika window-nya diekstrak jadi `storyPreloadWindow` (murni) agar
/// bisa dikunci tanpa membangun widget.
void main() {
  group('storyPreloadWindow', () {
    test('slide 0 → window 0..ahead (tanpa index negatif)', () {
      expect(storyPreloadWindow(0, 10, 2), [0, 1, 2]);
    });

    test('slide tengah → satu sebelum + ahead', () {
      expect(storyPreloadWindow(5, 10, 2), [4, 5, 6, 7]);
    });

    test('slide terakhir → di-clamp ke total-1', () {
      expect(storyPreloadWindow(9, 10, 2), [8, 9]);
    });

    test('slide kedua-dari-akhir → tetap benar di tepi', () {
      expect(storyPreloadWindow(8, 10, 2), [7, 8, 9]);
    });

    test('list kosong → []', () {
      expect(storyPreloadWindow(0, 0, 2), isEmpty);
    });

    test('total negatif (defensif) → []', () {
      expect(storyPreloadWindow(0, -3, 2), isEmpty);
    });

    test('slide tunggal → [0]', () {
      expect(storyPreloadWindow(0, 1, 2), [0]);
    });

    test('ahead=0 → hanya slide itu + satu sebelumnya', () {
      expect(storyPreloadWindow(3, 10, 0), [2, 3]);
    });

    test('start di luar batas (>= total) tetap di-clamp', () {
      final w = storyPreloadWindow(99, 10, 2);
      expect(w, isNotEmpty);
      expect(w.every((i) => i >= 0 && i <= 9), isTrue);
    });

    test('window tidak pernah keluar rentang [0, total-1]', () {
      for (var start = -2; start < 14; start++) {
        for (final total in [1, 3, 10]) {
          final w = storyPreloadWindow(start, total, 2);
          expect(w.every((i) => i >= 0 && i < total), isTrue,
              reason: 'start=$start total=$total → $w');
        }
      }
    });
  });

  group('slideCacheShouldEvict (cap LRU 60→8)', () {
    test('size <= max → tidak buang', () {
      expect(slideCacheShouldEvict(8), isFalse);
    });

    test('size > max → buang', () {
      expect(slideCacheShouldEvict(9), isTrue);
    });

    test('max default = 8 (kontrak RAM: ~40MB, bukan ~300MB)', () {
      expect(slideCacheShouldEvict(8), isFalse);
      expect(slideCacheShouldEvict(9), isTrue);
    });

    test('max dapat dioverride', () {
      expect(slideCacheShouldEvict(3, max: 2), isTrue);
      expect(slideCacheShouldEvict(2, max: 2), isFalse);
    });
  });
}
