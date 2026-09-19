import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/utils.dart';

void main() {
  group('parseDate', () {
    test('DateTime diteruskan apa adanya', () {
      final d = DateTime(2026, 5, 4, 3, 2, 1);
      expect(parseDate(d), d);
    });

    test('String ISO valid → DateTime (di-local)', () {
      final dt = parseDate('2026-05-04T03:02:01Z');
      expect(dt.isUtc, isFalse);
      expect(dt.toUtc().year, 2026);
      expect(dt.toUtc().hour, 3);
    });

    test('int = epoch ms', () {
      final dt = parseDate(0);
      expect(dt.millisecondsSinceEpoch, 0);
    });

    test('String tak valid → epoch 0', () {
      expect(parseDate('bukan-tanggal').millisecondsSinceEpoch, 0);
    });

    test('null → waktu sekarang (mendekati now)', () {
      final before = DateTime.now();
      final dt = parseDate(null);
      expect(dt.isBefore(before.subtract(const Duration(seconds: 5))), isFalse);
    });

    test('tipe tak dikenal → epoch 0', () {
      expect(parseDate(3.14).millisecondsSinceEpoch, 0);
    });
  });

  group('isValidEmail', () {
    test('email umum valid', () {
      for (final e in [
        'budi@contoh.com',
        'budi.santoso+tag@sub.contoh.co.id',
        'a_b-c%d@x-y.io',
        '  spasi@contoh.com  ',
      ]) {
        expect(isValidEmail(e), isTrue, reason: e);
      }
    });

    test('email tidak valid ditolak', () {
      for (final e in [
        '',
        'tanpa-at',
        '@tanpa-nama.com',
        'tanpa@domain',
        'spasi di@contoh.com',
        'double@@contoh.com',
      ]) {
        expect(isValidEmail(e), isFalse, reason: 'seharusnya tolak: $e');
      }
    });
  });

  group('isValidNickname', () {
    test('nickname wajar valid', () {
      for (final n in ['Budi', 'Budi Santoso', 'budi_123', 'a-b-c', 'Ñuño']) {
        expect(isValidNickname(n), isTrue, reason: n);
      }
    });

    test('emoji bukan huruf/angka → ditolak', () {
      expect(isValidNickname('Sari🌻'), isFalse);
    });

    test('terlalu pendek / panjang ditolak', () {
      expect(isValidNickname('ab'), isFalse);
      expect(isValidNickname('a' * 21), isFalse);
    });

    test('kosong / hanya spasi ditolak', () {
      expect(isValidNickname(''), isFalse);
      expect(isValidNickname('   '), isFalse);
    });

    test('karakter terlarang ditolak', () {
      expect(isValidNickname('budi@mail'), isFalse);
      expect(isValidNickname('budi!'), isFalse);
    });

    test('spasi pinggir di-trim (3-20 dihitung setelah trim)', () {
      expect(isValidNickname('  Budi  '), isTrue);
    });
  });

  group('normalizeNicknameForBan', () {
    test('lowercase + buang spasi/underscore/dash', () {
      expect(normalizeNicknameForBan('  ZAINI-HAFID '), 'zainihafid');
      expect(normalizeNicknameForBan('Zaini_Hafid'), 'zainihafid');
      expect(normalizeNicknameForBan('Bud i'), 'budi');
    });
  });

  group('colorHashForUid', () {
    test('deterministik per uid', () {
      expect(colorHashForUid('abc'), colorHashForUid('abc'));
    });

    test('selalu non-negatif', () {
      for (final u in ['', 'a', 'uid-123', 'z' * 40]) {
        expect(colorHashForUid(u), greaterThanOrEqualTo(0));
      }
    });

    test('uid beda umumnya hash beda', () {
      expect(colorHashForUid('uid-1'), isNot(colorHashForUid('uid-2')));
    });
  });

  group('formatBubbleTime', () {
    test('format 12 jam + AM/PM', () {
      final s = formatBubbleTime(DateTime(2026, 1, 2, 14, 30));
      expect(s, contains('2:30'));
      expect(s.toUpperCase(), contains('PM'));
    });

    test('pagi = AM', () {
      final s = formatBubbleTime(DateTime(2026, 1, 2, 9, 5));
      expect(s, contains('9:05'));
      expect(s.toUpperCase(), contains('AM'));
    });
  });

  group('formatTime', () {
    test('hari ini = jam saja', () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 8, 15);
      final out = formatTime(today);
      expect(out, contains('8:15'));
      expect(out, isNot(contains('Yesterday')));
    });

    test('kemarin diawali "Yesterday"', () {
      final y = DateTime.now().subtract(const Duration(days: 1));
      final out = formatTime(y);
      expect(out, startsWith('Yesterday'));
    });

    test('lebih dari 7 hari pakai tanggal', () {
      final old = DateTime.now().subtract(const Duration(days: 30));
      final out = formatTime(old);
      expect(out, isNot(contains('Yesterday')));
      expect(out, isNotEmpty);
    });
  });

  group('isValidImageBase64', () {
    test('header JPEG/PNG/WebP diterima', () {
      expect(isValidImageBase64('/9j/abc'), isTrue);
      expect(isValidImageBase64('iVBORw0KGgoABC'), isTrue);
      expect(isValidImageBase64('UklGRabc'), isTrue);
    });

    test('header dengan spasi pinggir tetap diterima', () {
      expect(isValidImageBase64('  /9j/abc  '), isTrue);
    });

    test('kosong / bukan gambar ditolak', () {
      expect(isValidImageBase64(''), isFalse);
      expect(isValidImageBase64('https://contoh.com/x.jpg'), isFalse);
      expect(isValidImageBase64('random'), isFalse);
    });
  });
}
