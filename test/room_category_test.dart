import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/room_categories.dart';
import 'package:chatyuk/config/strings.dart';

/// Mengunci kategori GLOBAL ROOM — chip "Jual Beli" (id 'jualbeli') harus
/// ada di config klien DAN punya label bilingual, karena server menolak
/// kategori yang tak dikenal ("Invalid category").
void main() {
  test('kategori jualbeli ada di roomCategories', () {
    final ids = roomCategories.map((c) => c['id']).toList();
    expect(ids, contains('jualbeli'));
    final jb = roomCategories.firstWhere((c) => c['id'] == 'jualbeli');
    expect(jb['icon'], '🛒');
    expect(jb['name'], 'Jual Beli');
  });

  test('id kategori unik (tidak ada duplikat)', () {
    final ids = roomCategories.map((c) => c['id']).toList();
    expect(ids.toSet().length, ids.length);
  });

  test('jualbeli punya label + deskripsi bilingual', () {
    final id = S(isId: true);
    final en = S(isId: false);
    expect(id.roomName('jualbeli'), 'Jual Beli');
    expect(en.roomName('jualbeli'), 'Buy & Sell');
    expect(id.roomDesc('jualbeli'), isNotEmpty);
    expect(en.roomDesc('jualbeli'), isNotEmpty);
  });
}
