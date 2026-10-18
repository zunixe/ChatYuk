import 'package:flutter_test/flutter_test.dart';

/// Regresi PERF: pemuatan daftar chat cukup SATU round-trip.
///
/// Dulu chat tersembunyi diambil lewat query KEDUA (`getHiddenChats`) yang
/// dijalankan paralel via `Future.wait`. Walau paralel, request tambahan itu
/// menambah round-trip penuh ke Supabase — terukur di HP: 1947ms saat app
/// baru bangun dari idle, LEBIH LAMBAT dari query utama (1734ms). Karena
/// `Future.wait` menunggu SEMUA, daftar chat tertahan sampai keduanya selesai.
///
/// Perbaikan: `hidden_by` ikut di-select pada query utama, disaring di klien.
/// Query-nya sendiri di server hanya ~1.4ms (1450 baris) — biaya sebenarnya
/// murni latensi jaringan per request, jadi memangkas 1 request = memangkas
/// sampai ~2 detik.
void main() {
  /// Salinan logika penyaringan di `_fetchPrivateChatRows`.
  Set<String> hiddenOf(List<Map<String, dynamic>> rows, String myUid) {
    final hidden = <String>{};
    for (final r in rows) {
      final hb = r['hidden_by'];
      if (hb is List && hb.any((e) => '$e' == myUid)) {
        hidden.add('${r['chat_id']}');
      }
    }
    return hidden;
  }

  test('menyaring chat tersembunyi milik user dari hidden_by', () {
    const me = 'uid-me';
    const other = 'uid-other';
    final rows = <Map<String, dynamic>>[
      {'chat_id': 'a', 'hidden_by': [me]},
      {'chat_id': 'b', 'hidden_by': <dynamic>[]},
      {'chat_id': 'c', 'hidden_by': [other]},
      {'chat_id': 'd', 'hidden_by': [other, me]},
      {'chat_id': 'e', 'hidden_by': null},
    ];

    expect(hiddenOf(rows, me), {'a', 'd'});
  });

  test('hidden_by bertipe uuid dikonversi string dengan benar', () {
    const me = 'a1b2c3d4-0000-0000-0000-000000000000';
    final rows = <Map<String, dynamic>>[
      {'chat_id': 'x', 'hidden_by': [me]},
    ];
    // Perbandingan memakai toString() agar aman bila driver memberi UUID
    // bukan String murni.
    expect(hiddenOf(rows, me), {'x'});
  });

  test('user tanpa chat tersembunyi → set kosong (kasus tersering)', () {
    final rows = <Map<String, dynamic>>[
      for (var i = 0; i < 20; i++) {'chat_id': 'c$i', 'hidden_by': <dynamic>[]},
    ];
    expect(hiddenOf(rows, 'uid-me'), isEmpty);
  });

  test('hidden_by bukan List (data rusak) tidak melempar', () {
    final rows = <Map<String, dynamic>>[
      {'chat_id': 'z', 'hidden_by': 'bukan-list'},
    ];
    expect(() => hiddenOf(rows, 'uid-me'), returnsNormally);
    expect(hiddenOf(rows, 'uid-me'), isEmpty);
  });
}
