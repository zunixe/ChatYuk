import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/nav_guard.dart';

/// Regresi "tombol back tidak bisa diklik, tapi scroll jalan" (bukan freeze).
///
/// Akar: tap 2× cepat saat transisi push belum selesai menumpuk 2 route
/// identik → 1× back hanya menutup route atas → layar tampak sama.
/// Guard [tryClaimNav]/[releaseNav] menutup celah ini untuk SEMUA pintu
/// navigasi (user & admin). Lihat docs/PERFORMANCE.md §18.
void main() {
  setUp(resetNavClaims);
  tearDown(resetNavClaims);

  test('klaim pertama lolos, klaim kedua cepat (key sama) ditolak', () {
    final t0 = DateTime.utc(2026, 9, 28, 10, 0, 0);
    final k = navKeyChat('a_b');
    expect(tryClaimNav(k, now: t0), isTrue);
    expect(
      tryClaimNav(k, now: t0.add(const Duration(milliseconds: 500))),
      isFalse,
    );
  });

  test('setelah release (route di-pop) klaim berikutnya lolos lagi', () {
    final t0 = DateTime.utc(2026, 9, 28, 10, 0, 0);
    final k = navKeyChat('a_b');
    expect(tryClaimNav(k, now: t0), isTrue);
    releaseNav(k);
    expect(
      tryClaimNav(k, now: t0.add(const Duration(milliseconds: 500))),
      isTrue,
    );
  });

  test('klaim basi (>2 dtk) lolos walau tanpa release', () {
    final t0 = DateTime.utc(2026, 9, 28, 10, 0, 0);
    final k = navKeyRoom('room-1');
    expect(tryClaimNav(k, now: t0), isTrue);
    expect(tryClaimNav(k, now: t0.add(const Duration(seconds: 3))), isTrue);
  });

  test('key kosong selalu lolos (tak ada yang didedupe)', () {
    expect(tryClaimNav(''), isTrue);
    expect(tryClaimNav(''), isTrue);
    releaseNav('');
  });

  test('key beda tidak saling memblokir (chat vs room vs user)', () {
    final t0 = DateTime.utc(2026, 9, 28, 10, 0, 0);
    final at = t0.add(const Duration(milliseconds: 100));
    expect(tryClaimNav(navKeyChat('x'), now: at), isTrue);
    expect(tryClaimNav(navKeyRoom('x'), now: at), isTrue);
    expect(tryClaimNav(navKeyUser('x'), now: at), isTrue);
  });

  test('window custom dihormati', () {
    final t0 = DateTime.utc(2026, 9, 28, 10, 0, 0);
    final k = navKeyUser('u1');
    expect(tryClaimNav(k, now: t0, window: const Duration(seconds: 5)), isTrue);
    expect(
      tryClaimNav(k, now: t0.add(const Duration(seconds: 3)),
          window: const Duration(seconds: 5)),
      isFalse,
    );
  });
}
