import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/screens/admin_dummy_tab.dart';

/// Mengunci perilaku filter tipe (`kind`) + pencarian nickname pada daftar
/// dummy admin. `kind` diisi dari RPC admin_list_dummies (kolom baru).
void main() {
  final items = <Map<String, dynamic>>[
    {'nickname': 'SoftwareExpert', 'kind': 'expert'},
    {'nickname': 'HardwareExpert', 'kind': 'expert'},
    {'nickname': 'Budi', 'kind': 'regular'},
    {'nickname': 'Santi', 'kind': 'regular'},
    // Baris lama tanpa `kind` → dianggap regular (defensif).
    {'nickname': 'Legacy'},
  ];

  group('filterDummies — filter kind', () {
    test('kind null = semua item', () {
      expect(filterDummies(items).length, 5);
    });

    test("kind 'expert' = hanya expert", () {
      final r = filterDummies(items, kind: 'expert');
      expect(r.map((m) => m['nickname']), ['SoftwareExpert', 'HardwareExpert']);
    });

    test("kind 'regular' = regular + item tanpa kind", () {
      final r = filterDummies(items, kind: 'regular');
      expect(r.map((m) => m['nickname']), ['Budi', 'Santi', 'Legacy']);
    });
  });

  group('filterDummies — pencarian nickname', () {
    test('case-insensitive substring', () {
      final r = filterDummies(items, search: 'expert');
      expect(r.length, 2);
    });

    test('search + kind digabung (AND)', () {
      final r = filterDummies(items, search: 'budi', kind: 'regular');
      expect(r.map((m) => m['nickname']), ['Budi']);
    });

    test('search expert + kind regular = kosong', () {
      expect(filterDummies(items, search: 'expert', kind: 'regular'), isEmpty);
    });

    test('search tanpa hasil = kosong', () {
      expect(filterDummies(items, search: 'zzz'), isEmpty);
    });
  });

  group('filterDummies — tepi', () {
    test('item nickname null tidak crash', () {
      final r = filterDummies([
        {'nickname': null, 'kind': 'regular'},
      ], search: 'a');
      expect(r, isEmpty);
    });

    test('daftar kosong = kosong', () {
      expect(filterDummies(const [], kind: 'expert'), isEmpty);
    });

    test('search spasi saja lolos (substring kosong)', () {
      // ' '.toLowerCase() = ' ' → tetap substring; nickname tak mengandung ' '.
      expect(filterDummies(items, search: ' '), isEmpty);
    });
  });

  group('filterDummies — kontrak tipe (kind dari RPC admin)', () {
    test('kind expert + search menyaring dua-duanya', () {
      final r = filterDummies(items, search: 'hardware', kind: 'expert');
      expect(r.map((m) => m['nickname']), ['HardwareExpert']);
    });

    test('search tidak di-trim (spasi pinggir = tak cocok)', () {
      expect(filterDummies(items, search: ' Budi '), isEmpty);
      expect(filterDummies(items, search: 'Budi').length, 1);
    });

    test('kind peka huruf besar/kecil (nilai dari server lower-case)', () {
      expect(filterDummies(items, kind: 'EXPERT'), isEmpty);
      expect(filterDummies(items, kind: 'expert').length, 2);
    });

    test('hasil filter = list baru, input tidak diubah', () {
      final asli = List<Map<String, dynamic>>.from(items);
      final r = filterDummies(items, kind: 'expert');
      expect(identical(r, items), isFalse);
      expect(items.length, asli.length);
      expect(items.map((m) => m['nickname']).toList(),
          asli.map((m) => m['nickname']).toList());
    });
  });
}
