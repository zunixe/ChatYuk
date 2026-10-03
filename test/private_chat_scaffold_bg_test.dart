import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/screens/private_chat_screen.dart';

/// Regresi GLITCH halaman sebelumnya saat buka profil dari avatar private chat.
///
/// Gejala (laporan user): saat ketuk avatar di header private chat → membuka
/// UserInfoScreen, SEKILAT terlihat daftar chat/online + ikon avatar inisial
/// di belakang. Penyebab: Scaffold private chat dulu `Colors.transparent` —
/// selama animasi push/pop, route transparan membocorkan halaman DI BAWAH-nya.
///
/// Fix: latar Scaffold dijadikan OPAQUE (`privateChatScaffoldBg` = bgScreen,
/// identik visual dengan Container bg di body). Test ini mengunci invarian:
/// warna latar TIDAK BOLEH kembali transparan / punya alpha < 1.
void main() {
  group('private chat Scaffold — latar OPAQUE (anti bocor transisi)', () {
    test('warna latar bukan transparan', () {
      expect(privateChatScaffoldBg, isNot(Colors.transparent));
      expect(privateChatScaffoldBg.a, 1.0,
          reason: 'alpha harus 1.0 (opaque penuh)');
    });

    test('alpha = 1.0 (tidak ada kebocoran tembus pandang)', () {
      expect(privateChatScaffoldBg.a, greaterThanOrEqualTo(1.0));
    });

    test('sama dengan bgScreen (konsisten dgn Container bg di body)', () {
      // Body private chat menggambar Container(color: AppTheme.bgScreen) full
      // screen; Scaffold memakai warna yang SAMA supaya transisi tak berubah
      // tampilan tapi menutup kebocoran route di bawah.
      expect(privateChatScaffoldBg, AppTheme.bgScreen);
    });

    test('warna solid (R/G/B tidak semuanya 0 = hitam transparan)', () {
      // Pengaman tambahan: pastikan bukan Colors.black dengan alpha 0 dsb.
      expect(privateChatScaffoldBg.a, 1.0);
      // bgScreen harus warna nyata (bukan placeholder default 0,0,0,0).
      final isOpaqueBlank =
          privateChatScaffoldBg.r == 0 &&
          privateChatScaffoldBg.g == 0 &&
          privateChatScaffoldBg.b == 0 &&
          privateChatScaffoldBg.a == 0;
      expect(isOpaqueBlank, isFalse);
    });
  });

  group('private chat route — anti-regresi transparansi', () {
    test('konstanta latar dapat diandalkan (dipakai Scaffold.backgroundColor)',
        () {
      // Jika seseorang mengembalikan ke Colors.transparent, nilai alpha akan
      // < 1 dan dua assertion di grup atas GAGAL — perlindungan otomatis.
      expect(privateChatScaffoldBg.a, 1.0);
    });
  });
}
