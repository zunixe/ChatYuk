import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/chat/banned_nicknames.dart';
import 'package:chatyuk/utils.dart';

/// REVIEW_2026-10-24 BUG-05: daftar kata terlarang tidak lagi hardcode di APK,
/// tapi dibaca dari `app_settings.banned_nicknames` dengan fallback bawaan.
/// Test ini mengunci perilaku normalisasi + fallback (guard tidak boleh
/// terbuka hanya karena server tidak terbaca).
void main() {
  group('BannedNicknames (fallback bawaan)', () {
    test('default menangkap variasi penulisan', () {
      for (final n in [
        'zaini',
        'ZAINI',
        'Za-Ini',
        'zaini_hafid',
        'zainihafid',
        'HAFID',
      ]) {
        expect(isBannedNickname(n), isTrue, reason: 'harus ditolak: $n');
      }
    });

    test('nama normal tidak tertolak', () {
      for (final n in ['Budi', 'Siti Nurhaliza', 'Andi99', 'Rizky']) {
        expect(isBannedNickname(n), isFalse, reason: 'harus diterima: $n');
      }
    });

    test('nama kosong / spasi saja tidak tertolak', () {
      expect(isBannedNickname(''), isFalse);
      expect(isBannedNickname('   '), isFalse);
    });
  });

  group('BannedNicknames.setFromServer', () {
    test('daftar dari server menggantikan bawaan', () {
      addTearDown(() => BannedNicknames.setFromServer(BannedNicknames.defaults));
      BannedNicknames.setFromServer(['penipu', 'scammer']);
      expect(isBannedNickname('PENIPU'), isTrue);
      expect(isBannedNickname('scam-mer'), isTrue);
      // Nama bawaan tidak lagi terlarang setelah server menggantinya.
      expect(isBannedNickname('zaini'), isFalse);
    });

    test('daftar kosong dari server TIDAK membuka guard', () {
      addTearDown(() => BannedNicknames.setFromServer(BannedNicknames.defaults));
      BannedNicknames.setFromServer(BannedNicknames.defaults);
      expect(isBannedNickname('zaini'), isTrue);
      BannedNicknames.setFromServer(const []);
      expect(
        isBannedNickname('zaini'),
        isTrue,
        reason: 'daftar kosong tidak boleh menghapus proteksi',
      );
    });

    test('entry berisi spasi/dash dinormalisasi', () {
      addTearDown(() => BannedNicknames.setFromServer(BannedNicknames.defaults));
      BannedNicknames.setFromServer(['Bad Name', 'evil-guy']);
      expect(isBannedNickname('badname'), isTrue);
      expect(isBannedNickname('EVILGUY'), isTrue);
    });
  });

  test('normalizeForBan membuang spasi/underscore/dash + lowercase', () {
    expect(normalizeForBan('  Za In-i_Hafid '), 'zainihafid');
  });
}
