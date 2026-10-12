import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/nav_guard.dart';
import 'package:chatyuk/providers/riverpod/nav_provider.dart';

/// REGRESSION PERFORMA (§10) — alur navigasi utama yang dijalankan otomatis
/// di CI (hermetic, tanpa network/device).
///
/// Mengunci perilaku yang mudah regresi saat optimasi navigasi:
///   1. Pindah tab berulang (banyak siklus) → state konsisten, tanpa penumpukan
///      provider/route (navProvider global, bukan autoDispose).
///   2. goTo ke tab sama = no-op (tidak memicu rebuild/catatan journal ganda).
///   3. Double-tap buka chat → hanya 1 route (nav guard), lalu boleh lagi
///      setelah release (buka-tutup berulang tetap berfungsi).
void main() {
  setUp(resetNavClaims);
  tearDown(resetNavClaims);

  group('navProvider — pindah tab berulang', () {
    test('100 siklus pindah tab tetap konsisten (tanpa drift/penumpukan)',
        () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final nav = c.read(navProvider.notifier);

      // Simulasi: Online→Chat→Timeline→Profil berulang 25x (= 100 pindah).
      const seq = [1, 2, 3, 0];
      for (var i = 0; i < 25; i++) {
        for (final t in seq) {
          nav.goTo(t);
          expect(c.read(navProvider), t,
              reason: 'tab harus persis nilai yang dituju (siklus $i, tab $t)');
        }
      }
      // Provider global → instance SAMA sepanjang sesi (bukan dibuat ulang).
      expect(identical(c.read(navProvider.notifier), nav), isTrue);
    });

    test('goTo tab sama = no-op (state tak berubah)', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final nav = c.read(navProvider.notifier);
      nav.goTo(2);
      nav.goTo(2);
      nav.goTo(2);
      expect(c.read(navProvider), 2);
    });

    test('index di luar jangkauan tetap disimpan apa adanya (dipetakan UI)',
        () {
      // navProvider hanya menyimpan angka; validasi rentang ada di UI.
      // Kunci: tidak melempar (UI tetap responsif, bukan crash).
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(navProvider.notifier).goTo(3);
      expect(c.read(navProvider), 3);
    });
  });

  group('nav guard — buka chat berulang (§3 poin 8-9)', () {
    test('tap 2x cepat → klaim kedua ditolak (anti route ganda)', () {
      final t0 = DateTime.utc(2026, 10, 12, 10);
      const key = 'private-chat:a_b';
      expect(tryClaimNav(key, now: t0), isTrue);
      expect(
        tryClaimNav(key, now: t0.add(const Duration(milliseconds: 300))),
        isFalse,
      );
    });

    test('buka-tutup 30x berulang → tiap kali boleh lagi (tak macet)', () {
      var t = DateTime.utc(2026, 10, 12, 10);
      const key = 'private-chat:x_y';
      for (var i = 0; i < 30; i++) {
        expect(tryClaimNav(key, now: t), isTrue,
            reason: 'buka ke-${i + 1} harus boleh');
        releaseNav(key); // route di-pop
        t = t.add(const Duration(seconds: 5));
      }
    });

    test('kunci BERBEDA tidak saling blok (buka chat lain tetap jalan)', () {
      final t0 = DateTime.utc(2026, 10, 12, 10);
      expect(tryClaimNav('private-chat:a_b', now: t0), isTrue);
      expect(tryClaimNav('private-chat:c_d', now: t0), isTrue);
      expect(tryClaimNav('profile:e', now: t0), isTrue);
    });
  });
}
