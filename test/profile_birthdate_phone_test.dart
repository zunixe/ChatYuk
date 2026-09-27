import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/utils.dart' show dateOnly, normalizePhone;

/// Tanggal lahir & Nomor HP (Pengaturan › Akun): helper murni + parsing model.
void main() {
  group('normalizePhone', () {
    test('buang spasi, tanda hubung, kurung', () {
      expect(normalizePhone('+62 812-3456-7890'), '+6281234567890');
      expect(normalizePhone('(0812) 3456 7890'), '081234567890');
    });

    test('pertahankan + di depan saja', () {
      expect(normalizePhone('+62812'), '+62812');
      expect(normalizePhone('62812'), '62812');
      // '+' yang muncul di tengah diabaikan (hanya digit tetap).
      expect(normalizePhone('62+812'), '62812');
    });

    test('kosong / tanpa digit → string kosong', () {
      expect(normalizePhone(''), '');
      expect(normalizePhone('   '), '');
      expect(normalizePhone('abc'), '');
      expect(normalizePhone('+'), '');
    });
  });

  group('dateOnly', () {
    test('format YYYY-MM-DD dengan padding', () {
      expect(dateOnly(DateTime(1998, 8, 7)), '1998-08-07');
      expect(dateOnly(DateTime(2001, 12, 31)), '2001-12-31');
      expect(dateOnly(DateTime(2026, 1, 1)), '2026-01-01');
    });
  });

  group('UserModel birthDate & phone', () {
    UserModel base(Map<String, dynamic> extra) => UserModel.fromMap('u-1', {
          'nickname': 'Budi',
          'gender': 'male',
          'age': 20,
          ...extra,
        });

    test('birth_date (snake_case) diparse ke DateTime tanggal saja', () {
      final u = base({'birthDate': '1998-08-07'});
      expect(u.birthDate, DateTime(1998, 8, 7));
    });

    test('birthDate camelCase juga diterima', () {
      final u = base({'birthDate': '2001-12-31'});
      expect(u.birthDate, DateTime(2001, 12, 31));
    });

    test('birthDate kosong/null → null', () {
      expect(base({'birthDate': ''}).birthDate, isNull);
      expect(base({}).birthDate, isNull);
    });

    test('phone terbaca; default kosong', () {
      expect(base({'phone': '+6281234567890'}).phone, '+6281234567890');
      expect(base({}).phone, '');
    });

    test('copyWith birthDate & phone', () {
      final u = base({}).copyWith(
        birthDate: DateTime(1990, 5, 17),
        phone: '+62811',
      );
      expect(u.birthDate, DateTime(1990, 5, 17));
      expect(u.phone, '+62811');
    });
  });
}
