import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/providers/admin_provider.dart';

/// Merge monitor chat: id baru disisipkan (urutan DESC terjaga), baris
/// dikenal yang berubah (dihapus/diedit) ditimpa, identik = diam.
/// Regresi kasus nyata: pesan yang dihapus terjebak tampil konten lama
/// selamanya (merge skip id dikenal + banding layar cuma id+teks).
void main() {
  Map<String, dynamic> row(
    int id, {
    String text = 'x',
    String type = 'text',
    bool deleted = false,
    bool edited = false,
  }) =>
      {
        'id': id,
        'sender_id': 'u1',
        'text': text,
        'type': type,
        'is_deleted': deleted,
        'edited': edited,
        'image_data': '',
        'image_path': '',
        'voice_path': '',
      };

  test('pesan baru disisipkan di depan, urutan DESC terjaga', () {
    final res = mergeAdminChatMessages(
      [row(2, text: 'b'), row(1, text: 'a')],
      [row(4, text: 'd'), row(3, text: 'c')],
    );
    expect(res.changed, isTrue);
    expect(
      res.merged.map((m) => m['id']).toList(),
      [4, 3, 2, 1],
    );
  });

  test('soft-delete baris dikenal menimpa (changed)', () {
    final res = mergeAdminChatMessages(
      [row(2, text: 'b'), row(1, text: 'Hai')],
      [row(2, text: 'b'), row(1, text: 'Hai', deleted: true)],
    );
    expect(res.changed, isTrue);
    expect(res.merged.length, 2);
    expect(res.merged[1]['is_deleted'], isTrue);
  });

  test('edit teks baris dikenal menimpa (changed)', () {
    final res = mergeAdminChatMessages(
      [row(1, text: 'lama')],
      [row(1, text: 'baru', edited: true)],
    );
    expect(res.changed, isTrue);
    expect(res.merged.single['text'], 'baru');
  });

  test('identik = diam (tanpa notify tak perlu)', () {
    final cur = [row(2, text: 'b'), row(1, text: 'a')];
    final res = mergeAdminChatMessages(
      cur,
      [row(2, text: 'b'), row(1, text: 'a')],
    );
    expect(res.changed, isFalse);
    expect(res.merged.length, 2);
  });

  test('latest kosong = diam', () {
    final res = mergeAdminChatMessages([row(1)], const []);
    expect(res.changed, isFalse);
  });

  test('campuran baru + hapus sekaligus', () {
    final res = mergeAdminChatMessages(
      [row(2, text: 'b'), row(1, text: 'a')],
      [row(3, text: 'c'), row(1, text: 'a', deleted: true)],
    );
    expect(res.changed, isTrue);
    expect(res.merged.map((m) => m['id']).toList(), [3, 2, 1]);
    expect(res.merged[2]['is_deleted'], isTrue);
  });
}
