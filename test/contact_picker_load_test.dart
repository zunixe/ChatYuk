import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/contact_picker_sheet.dart';

/// Regresi: sheet "Cari kontak" di tab ChatYuk DULU muter terus / kosong.
///
/// Akar masalah (sebelum perbaikan):
///  - `_loadUsers` mengambil `socialList('friends')` lalu `getMyPrivateChats`
///    secara BERURUTAN → total waktu = jumlah keduanya.
///  - `socialList` TIDAK punya timeout sama sekali → kalau RPC menggantung,
///    spinner `_loadingUsers` tidak pernah selesai ("muter terus").
///  - Tidak ada fast-path: daftar "orang yang pernah chat" yang sudah ada di
///    memori (snapshot tab Pesan) tidak dipakai, jadi menunggu jaringan dulu.
///
/// Perbaikan: snapshot memori dipakai SEKETIKA, lalu teman+chat diambil
/// PARALEL dengan timeout masing-masing.
void main() {
  group('mergePickerUsers — sumber daftar', () {
    test('teman ∪ pernah-chat, dedupe by uid', () {
      final out = mergePickerUsers(
        friends: [
          {'uid': 'u1', 'nickname': 'Ani', 'gender': 'female', 'avatar': 'a1'},
          {'uid': 'u2', 'nickname': 'Budi', 'gender': 'male', 'avatar': 'a2'},
        ],
        chatted: [
          (uid: 'u1', name: 'Ani (chat)', gender: 'female'),
          (uid: 'u3', name: 'Citra', gender: 'female'),
        ],
      );
      expect(out.map((e) => e.uid).toList(), ['u1', 'u2', 'u3']);
      // Teman menang (punya avatar), bukan versi chat.
      expect(out.first.name, 'Ani');
      expect(out.first.avatar, 'a1');
      expect(out.last.name, 'Citra');
    });

    test('hanya "pernah chat" (tanpa teman) tetap tampil', () {
      final out = mergePickerUsers(
        friends: const [],
        chatted: [(uid: 'x', name: 'Xavier', gender: 'male')],
      );
      expect(out, hasLength(1));
      expect(out.single.uid, 'x');
    });

    test('hanya teman (tanpa chat) tetap tampil', () {
      final out = mergePickerUsers(
        friends: [
          {'uid': 'f', 'nickname': 'Fajar'},
        ],
        chatted: const [],
      );
      expect(out.single.name, 'Fajar');
    });

    test('uid kosong dibuang dari kedua sumber', () {
      final out = mergePickerUsers(
        friends: [
          {'uid': '', 'nickname': 'Kosong'},
          {'uid': 'ok', 'nickname': 'Ok'},
        ],
        chatted: [(uid: '', name: 'Rusak', gender: '')],
      );
      expect(out.map((e) => e.uid).toList(), ['ok']);
    });

    test('urutan abjad (case-insensitive)', () {
      final out = mergePickerUsers(
        friends: [
          {'uid': '1', 'nickname': 'zaki'},
          {'uid': '2', 'nickname': 'Budi'},
        ],
        chatted: [(uid: '3', name: 'agus', gender: 'male')],
      );
      expect(out.map((e) => e.name).toList(), ['agus', 'Budi', 'zaki']);
    });
  });

  testWidgets('sheet tidak menggantung: loading SELALU berakhir', (
    tester,
  ) async {
    // Regresi utama: `_loadUsers` dulu bisa MELEMPAR sebelum
    // `_loadingUsers = false` (mis. Supabase belum siap) → spinner abadi.
    // Sekarang body dibungkus try/finally, dan tiap fetch punya timeout.
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: Scaffold())),
    );
    await tester.pump();

    showContactPickerSheet(
      context: tester.element(find.byType(Scaffold)),
    );
    await tester.pump(); // buka sheet

    // Beri waktu beberapa frame + lewati batas timeout internal.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(seconds: 1));

    // HARUS berhenti memuat — entah menampilkan daftar atau empty-state.
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'loading tidak boleh menggantung selamanya',
    );
    // Dan tab ChatYuk tetap punya konten (empty-state), bukan layar kosong.
    expect(find.text('ChatYuk'), findsWidgets);
  });
}
