import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/moderation_texts.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/providers/riverpod/locale_provider.dart';

/// Regresi fitur moderasi (laporan user 2026-10-27):
///   * "klik ajukan gagal" — padahal akun SUDAH moderator; pesannya dulu
///     "lamaran menunggu" sehingga terasa gagal.
///   * "negara asal dipilih ga ada tulisan negaranya" — `??=` mengunci null
///     saat profil belum termuat.
///   * cooldown tidak menyebut tanggal.
void main() {
  final s = const LocaleState('id').s;

  group('moderationApplyMessage', () {
    test('sudah moderator TIDAK dilaporkan sebagai "menunggu"', () {
      final msg = moderationApplyMessage(
        {'ok': true, 'already_moderator': true},
        s,
      );
      expect(msg, s.moderationAlreadyModerator);
      expect(msg, isNot(s.moderationApplyPending));
    });

    test('lamaran pending dilaporkan menunggu', () {
      expect(
        moderationApplyMessage({'ok': true, 'already_pending': true}, s),
        s.moderationApplyPending,
      );
    });

    test('akun terlalu baru menyebut jumlah hari', () {
      final msg = moderationApplyMessage(
        {'ok': false, 'error': 'account_too_new', 'min_days': 7},
        s,
      );
      expect(msg, s.moderationApplyNeedDays(7));
      expect(msg, contains('7'));
    });

    test('pesan kurang menyebut punya vs butuh', () {
      final msg = moderationApplyMessage(
        {
          'ok': false,
          'error': 'not_enough_messages',
          'need': 50,
          'have': 0,
        },
        s,
      );
      expect(msg, s.moderationApplyNeedMsgs(50, 0));
      expect(msg, contains('50'));
      expect(msg, contains('0'));
    });

    test('lamaran terkirim', () {
      expect(
        moderationApplyMessage({'ok': true, 'application_id': 12}, s),
        s.moderationApplySent,
      );
    });

    test('gagal tak dikenal → pesan generik', () {
      expect(moderationApplyMessage({'ok': false}, s), s.errGeneric);
    });

    test('default angka dipakai bila server tidak mengirim need/have', () {
      final msg = moderationApplyMessage(
        {'ok': false, 'error': 'not_enough_messages'},
        s,
      );
      expect(msg, s.moderationApplyNeedMsgs(50, 0));
    });
  });

  group('effectiveHomeCountry', () {
    test('pakai profil bila belum ada override', () {
      expect(
        effectiveHomeCountry(override: null, fromProfile: 'Armenia'),
        'Armenia',
      );
    });

    test('override user menang atas profil', () {
      expect(
        effectiveHomeCountry(override: 'Indonesia', fromProfile: 'Armenia'),
        'Indonesia',
      );
    });

    test('override KOSONG berarti di-unset, bukan kembali ke profil', () {
      // Inilah bug lama: nilai kosong jatuh kembali ke profil sehingga
      // "unset" tampak tidak berpengaruh.
      expect(
        effectiveHomeCountry(override: '', fromProfile: 'Armenia'),
        '',
      );
    });

    test('profil null → string kosong (bukan "null")', () {
      expect(effectiveHomeCountry(override: null, fromProfile: null), '');
    });
  });

  group('homeCountryCooldownMessage', () {
    test('menyebut TANGGAL bila server mengirim next_change_at', () {
      final msg = homeCountryCooldownMessage(
        {'ok': false, 'error': 'cooldown', 'next_change_at': '2026-11-25T10:00:00Z'},
        s,
      );
      expect(msg, contains('25/11/2026'));
      expect(msg, isNot(s.moderationCountryCooldown));
    });

    test('tanpa next_change_at → pesan cooldown umum', () {
      expect(
        homeCountryCooldownMessage({'ok': false, 'error': 'cooldown'}, s),
        s.moderationCountryCooldown,
      );
    });

    test('next_change_at rusak tidak crash', () {
      expect(
        homeCountryCooldownMessage({'next_change_at': 'bukan-tanggal'}, s),
        s.moderationCountryCooldown,
      );
    });

    test('tanggal satu digit diberi nol depan', () {
      final msg = homeCountryCooldownMessage(
        {'next_change_at': '2027-01-05T08:00:00Z'},
        s,
      );
      expect(msg, contains('05/01/2027'));
    });
  });
}
