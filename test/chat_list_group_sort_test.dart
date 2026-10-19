import 'package:flutter_test/flutter_test.dart';

/// Regresi: "Unsupported operation: Cannot modify an unmodifiable list".
///
/// Terbukti di device (logcat build profile, 2026-10-19 18:28):
///   #0 UnmodifiableListMixin.sort (dart:_internal/list.dart:147:5)
///   #1 _PcBuildMx.build.<anonymous closure>
///      (package:chatyuk/screens/private_chats/private_chats_build.dart:260:31)
///
/// Penyebabnya: daftar grup memakai `const <RoomModel>[]` (immutable) untuk
/// cabang "filter tidak menampilkan grup", lalu hasil ekspresi yang sama
/// dirantai `..sort(...)`. `sort` pada list `const` melempar UnsupportedError
/// → layar merah di halaman Pesan.
///
/// Test ini mengunci pola yang benar: SEBELUM di-sort, list harus mutable.
/// Ditulis sebagai unit test murni (tanpa widget) supaya cepat & tidak
/// bergantung pada Supabase.
void main() {
  group('daftar grup pada halaman Pesan aman di-sort', () {
    /// Meniru bentuk ekspresi di `private_chats_build.dart`: cabang kosong
    /// mengembalikan list baru, bukan `const []`.
    List<int> buildGroupItems({required bool showGroups}) {
      final myGroups = <int>[];
      return !showGroups
          ? <int>[]
          : (myGroups).where((g) => g > 0).toList()..sort((a, b) => a - b);
    }

    test('filter yang menyembunyikan grup tidak crash (dulu layar merah)', () {
      // Ini kasus yang memicu bug: showGroups == false.
      expect(() => buildGroupItems(showGroups: false), returnsNormally);
      expect(buildGroupItems(showGroups: false), isEmpty);
    });

    test('filter yang menampilkan grup juga aman', () {
      expect(() => buildGroupItems(showGroups: true), returnsNormally);
    });

    test('list hasil bisa dimodifikasi (bukan unmodifiable)', () {
      final items = buildGroupItems(showGroups: false);
      // sort() WAJIB berhasil — inilah yang gagal pada versi `const []`.
      expect(() => items.sort(), returnsNormally);
      // Mutasi lain juga harus boleh, membuktikan list benar-benar mutable.
      items.add(1);
      expect(items, [1]);
    });

    test('`const []` memang unmodifiable (bukti akar masalah)', () {
      // Menjaga asumsi test ini sendiri: kalau `const []` ternyata bisa
      // di-sort, test di atas tidak lagi membuktikan apa pun.
      const immutable = <int>[];
      expect(() => immutable.sort(), throwsUnsupportedError);
    });
  });
}
