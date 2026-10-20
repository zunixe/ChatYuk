import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/media/chat_photo_helper.dart';

/// Keluhan 2026-10-20: foto SEKALI-LIHAT potret tampak "padding besar" di
/// kiri-kanan karena kotak memakai `chatPhotoSize` (tinggi maksimal 4/3 lebar)
/// lalu foto di-`contain` → bilah kosong. Helper baru `viewOncePhotoSize`
/// mengizinkan kartu potret lebih tinggi (maks 1.5× lebar) dan kartu dirender
/// `BoxFit.cover`, sehingga foto selalu mengisi lebar kolom.
void main() {
  const w = 300.0;

  test('potret 9:16 memakai tinggi penuh 1.5× lebar (tidak gepeng)', () {
    final s = viewOncePhotoSize(1080, 1920, w);
    expect(s.width, w);
    expect(s.height, w * 1.5);
  });

  test('potret 3:4 → tinggi mengikuti aspek (0.75 lebar? tidak — 1.33×)', () {
    final s = viewOncePhotoSize(900, 1200, w);
    expect(s.width, w);
    expect(s.height, closeTo(w * 1200 / 900, 0.001));
  });

  test('lanskap 16:9 → tinggi mengikuti aspek (0.5625 lebar)', () {
    final s = viewOncePhotoSize(1920, 1080, w);
    expect(s.width, w);
    expect(s.height, closeTo(w * 1080 / 1920, 0.001));
  });

  test('gambar sangat lebar (4:1) dibatasi 0.5× lebar (dipotong cover)', () {
    final s = viewOncePhotoSize(4000, 1000, w);
    expect(s.width, w);
    expect(s.height, closeTo(w * 0.5, 0.001));
  });

  test('aspek tidak diketahui → kotak aman 4/3', () {
    final s = viewOncePhotoSize(0, 0, w);
    expect(s.width, w);
    expect(s.height, closeTo(w * 4 / 3, 0.001));
  });

  test('foto ekstrem tinggi tetap dibatasi 1.5× lebar (bukan tak terbatas)', () {
    final s = viewOncePhotoSize(600, 2400, w);
    expect(s.height, closeTo(w * 1.5, 0.001));
  });

  test('aspek terjaga kapan pun kartu tidak dibatasi (tidak ada bilah)', () {
    for (final dims in [
      (1080, 1200),
      (1080, 1440),
      (1080, 1600),
      (1080, 1500),
    ]) {
      final s = viewOncePhotoSize(dims.$1, dims.$2, w);
      expect(
        s.height / s.width,
        closeTo(dims.$2 / dims.$1, 0.001),
        reason: 'kartu $dims harus mengikuti aspek foto (tanpa letterbox)',
      );
    }
  });
}
