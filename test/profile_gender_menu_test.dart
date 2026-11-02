import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regresi: menu profil gender-specific + top-up ada di kartu kuning.
/// - female: kartu "Saldo" + "Bonus" (layar misi kini berjudul Bonus)
/// - male  : TIDAK ada kartu hijau duplikat; top-up lewat kartu YukCoin
///           kuning (_pointsInfo di profile_ui2.dart)
void main() {
  final ui = File('lib/screens/profile/profile_ui.dart').readAsStringSync();
  final ui2 = File('lib/screens/profile/profile_ui2.dart').readAsStringSync();



  test('blok female berisi Saldo + Bonus', () {
    final a = ui.indexOf('// Menu Saldo & Misi');
    expect(a, greaterThanOrEqualTo(0));
    final b = ui.indexOf('if (!isAnon)', a);
    final blok = ui.substring(a, b);
    expect(blok, contains('s.saldoTitle'));
    expect(blok, contains('s.bonusTitle'));
  });

  test('tidak ada kartu hijau duplikat untuk male', () {
    expect(ui, isNot(contains('_sideCard(\n                      icon: Icons.add_circle_outline')));
    expect(ui, isNot(contains('// Menu Top-up')));
  });

  test('kartu kuning YukCoin punya tombol top-up', () {
    expect(ui2, contains('_openTopupSheet'));
    expect(ui2, contains('s.yukcoinTopup'));
  });

  test('_openTopupSheet memakai NavGate (wiring main.dart)', () {
    expect(ui2, contains('NavGate.topupSheet'));
    expect(ui2, contains('show(context, s)'));
  });
}
