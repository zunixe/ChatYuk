import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/screens/profile_screen.dart';

/// Validasi kata konfirmasi hapus akun.
///
/// Bug yang dijaga: tombol hapus hanya aktif untuk kata sesuai locale
/// (HAPUS=id, DELETE=en) sehingga user yang mengetik kata "salah bahasa"
/// mengira hapus akun rusak. Sekarang kedua kata diterima di semua bahasa.
void main() {
  group('isDeleteAccountConfirmValid', () {
    test('HAPUS diterima', () {
      expect(isDeleteAccountConfirmValid('HAPUS'), isTrue);
    });

    test('DELETE diterima', () {
      expect(isDeleteAccountConfirmValid('DELETE'), isTrue);
    });

    test('case-insensitive + trim', () {
      expect(isDeleteAccountConfirmValid('hapus'), isTrue);
      expect(isDeleteAccountConfirmValid('delete'), isTrue);
      expect(isDeleteAccountConfirmValid('  Hapus  '), isTrue);
      expect(isDeleteAccountConfirmValid('  delete\n'), isTrue);
    });

    test('kata lain ditolak', () {
      expect(isDeleteAccountConfirmValid(''), isFalse);
      expect(isDeleteAccountConfirmValid('YA'), isFalse);
      expect(isDeleteAccountConfirmValid('HAPUSKAN'), isFalse);
      expect(isDeleteAccountConfirmValid('DELET'), isFalse);
      expect(isDeleteAccountConfirmValid('HAPUS DELETE'), isFalse);
    });
  });

  group('strings konfirmasi hapus akun (bilingual)', () {
    test('label menyebut kedua kata', () {
      expect(S(isId: true).labelDeleteAccountConfirm, contains('HAPUS'));
      expect(S(isId: true).labelDeleteAccountConfirm, contains('DELETE'));
      expect(S(isId: false).labelDeleteAccountConfirm, contains('HAPUS'));
      expect(S(isId: false).labelDeleteAccountConfirm, contains('DELETE'));
    });

    test('hint menyebut kedua kata', () {
      expect(S(isId: true).deleteAccountConfirmHint, 'HAPUS / DELETE');
      expect(S(isId: false).deleteAccountConfirmHint, 'HAPUS / DELETE');
    });
  });
}
