import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Higiene repo: JANGAN ada gambar (screenshot debug) di AKAR repo.
///
/// Screenshot sesi (capture HP, dump hasil SQL, dsb) pernah bocor & ter-commit
/// (~12MB blob). Aset resmi SELALU di folder khusus (assets/, store_assets/,
/// android/, ios/, web/, macos/, third_party/) — bukan akar.
///
/// `.gitignore` menolaknya (pola `/*.png` dst); test ini mengunci aturannya
/// supaya tetap terjaga walau .gitignore diubah tanpa sadar.
void main() {
  test('tidak ada gambar di akar repo (aset harus di folder khusus)', () {
    const exts = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};
    final hits = <String>[];
    // Pindai HANYA file top-level (non-rekursif) di direktori kerja (root
    // repo saat `flutter test`). Folder aset tak tersentuh.
    for (final e in Directory('.').listSync()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last.toLowerCase();
      if (exts.any(name.endsWith)) hits.add(name);
    }
    expect(
      hits,
      isEmpty,
      reason:
          'Gambar di AKAR repo terdeteksi (harus dihapus/dipindah ke folder '
          'aset):\n${hits.join('\n')}',
    );
  });
}
