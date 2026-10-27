import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/moderation_texts.dart';
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

    test('langsung ditetapkan → pesan selamat menyebut negara', () {
      final msg = moderationApplyMessage(
        {'ok': true, 'granted': true},
        s,
        country: 'Indonesia',
      );
      expect(msg, s.moderationGranted('Indonesia'));
      expect(msg, contains('Indonesia'));
    });

    test('slot penuh → pesan slots_full', () {
      final msg = moderationApplyMessage(
        {'ok': false, 'error': 'slots_full', 'max': 2},
        s,
      );
      expect(msg, s.moderationSlotsFull);
      expect(msg, contains('2'));
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

  group('moderationCardVisible (visibilitas kartu moderasi)', () {
    test('negara belum diatur → tampil (panel bantu atur dulu)', () {
      expect(
        moderationCardVisible(
          isAdmin: false,
          isModerator: false,
          hasPending: false,
          countrySet: false,
          eligible: false,
          slotOpen: false,
        ),
        isTrue,
      );
    });

    test('berwenang (admin/moderator/pending) → tampil walau slot penuh', () {
      for (final (isAdmin, isMod, pending) in [
        (true, false, false),
        (false, true, false),
        (false, false, true),
      ]) {
        expect(
          moderationCardVisible(
            isAdmin: isAdmin,
            isModerator: isMod,
            hasPending: pending,
            countrySet: true,
            eligible: false,
            slotOpen: false,
          ),
          isTrue,
          reason: 'isAdmin=$isAdmin isMod=$isMod pending=$pending',
        );
      }
    });

    test('slot penuh & bukan berwenang → DISUNGUI', () {
      expect(
        moderationCardVisible(
          isAdmin: false,
          isModerator: false,
          hasPending: false,
          countrySet: true,
          eligible: true,
          slotOpen: false,
        ),
        isFalse,
      );
    });

    test('belum memenuhi syarat → disungui walau slot terbuka', () {
      expect(
        moderationCardVisible(
          isAdmin: false,
          isModerator: false,
          hasPending: false,
          countrySet: true,
          eligible: false,
          slotOpen: true,
        ),
        isFalse,
      );
    });

    test('syarat terpenuhi + slot terbuka → tampil (siapa cepat dia dapat)',
        () {
      expect(
        moderationCardVisible(
          isAdmin: false,
          isModerator: false,
          hasPending: false,
          countrySet: true,
          eligible: true,
          slotOpen: true,
        ),
        isTrue,
      );
    });
  });

  group('effectiveCountry', () {
    test('pakai profil bila belum ada override', () {
      expect(
        effectiveCountry(override: null, fromProfile: 'Armenia'),
        'Armenia',
      );
    });

    test('override user menang atas profil', () {
      expect(
        effectiveCountry(override: 'Indonesia', fromProfile: 'Armenia'),
        'Indonesia',
      );
    });

    test('override KOSONG berarti di-unset, bukan kembali ke profil', () {
      // Inilah bug lama: nilai kosong jatuh kembali ke profil sehingga
      // "unset" tampak tidak berpengaruh.
      expect(
        effectiveCountry(override: '', fromProfile: 'Armenia'),
        '',
      );
    });

    test('profil null → string kosong (bukan "null")', () {
      expect(effectiveCountry(override: null, fromProfile: null), '');
    });
  });

  group('countryChangedMessage (info setelah ubah negara)', () {
    test('menyebut jabatan moderator yang dicabut', () {
      final msg = countryChangedMessage(
        {
          'ok': true,
          'country': 'Thailand',
          'revoked_moderator_for': ['Indonesia'],
          'next_change_at': '2026-11-03T10:00:00Z',
        },
        s,
      );
      expect(msg, s.moderationRevokedOnCountryChange('Indonesia'));
      expect(msg, contains('Indonesia'));
    });

    test('tanpa pencabutan → info kapan bisa diubah lagi', () {
      final msg = countryChangedMessage(
        {
          'ok': true,
          'country': 'Thailand',
          'revoked_moderator_for': <String>[],
          'next_change_at': '2026-11-03T10:00:00Z',
        },
        s,
      );
      expect(msg, s.moderationCountryChangedUntil('03/11/2026'));
    });

    test('revoked null tidak crash', () {
      final msg = countryChangedMessage(
        {'ok': true, 'next_change_at': '2026-11-03T10:00:00Z'},
        s,
      );
      expect(msg, contains('03/11/2026'));
    });
  });

  group('countryChangeConfirmBody (popup persetujuan)', () {
    test('moderator: menyebut jabatan akan DICABUT + negara lama/baru', () {
      final body = countryChangeConfirmBody(
        from: 'Indonesia',
        to: 'Thailand',
        moderating: 'Indonesia',
        lockUntil: '03/11/2026',
        s: s,
      );
      expect(body, s.moderationChangeCountryRevokeWarn(
        'Indonesia',
        'Thailand',
        '03/11/2026',
      ));
      expect(body.toUpperCase(), contains('CABUT'));
      expect(body, contains('Thailand'));
      expect(body, contains('50 pesan'));
    });

    test('bukan moderator: tetap beri tahu lock 7 hari', () {
      final body = countryChangeConfirmBody(
        from: 'Indonesia',
        to: 'Thailand',
        moderating: '',
        lockUntil: '03/11/2026',
        s: s,
      );
      expect(body, s.moderationChangeCountryWarn('Thailand', '03/11/2026'));
      expect(body, contains('7 hari'));
    });
  });

  group('moderationDate', () {
    test('format dd/MM/yyyy', () {
      expect(moderationDate('2026-11-03T10:00:00Z'), '03/11/2026');
    });
    test('null / kosong / rusak → null', () {
      expect(moderationDate(null), isNull);
      expect(moderationDate(''), isNull);
      expect(moderationDate('bukan-tanggal'), isNull);
    });
  });

  group('countryCooldownMessage', () {
    test('menyebut TANGGAL bila server mengirim next_change_at', () {
      final msg = countryCooldownMessage(
        {'ok': false, 'error': 'cooldown', 'next_change_at': '2026-11-25T10:00:00Z'},
        s,
      );
      expect(msg, contains('25/11/2026'));
      expect(msg, isNot(s.moderationCountryCooldown));
    });

    test('tanpa next_change_at → pesan cooldown umum', () {
      expect(
        countryCooldownMessage({'ok': false, 'error': 'cooldown'}, s),
        s.moderationCountryCooldown,
      );
    });

    test('next_change_at rusak tidak crash', () {
      expect(
        countryCooldownMessage({'next_change_at': 'bukan-tanggal'}, s),
        s.moderationCountryCooldown,
      );
    });

    test('tanggal satu digit diberi nol depan', () {
      final msg = countryCooldownMessage(
        {'next_change_at': '2027-01-05T08:00:00Z'},
        s,
      );
      expect(msg, contains('05/01/2027'));
    });
  });
}
