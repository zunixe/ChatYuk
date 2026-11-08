import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regresi: tab "Timeline" pernah menampilkan DOKUMENTASI karena label dan
/// isi ditulis sebagai dua daftar terpisah dan bergeser.
///
/// Sekarang panel admin = halaman utama ikon berkategori; label, ikon,
/// kategori dan isi semua diturunkan dari SATU enum `AdminMenu` lewat
/// `switch` lengkap di `admin_menu.dart`. Test ini mengunci: (1) daftar menu
/// tetap, (2) setiap menu punya arm di semua switch, (3) setiap menu tampil
/// tepat sekali di `adminMenuLayout` dan sesuai kategorinya.
void main() {
  final src =
      File('lib/screens/admin_panel/admin_menu.dart').readAsStringSync();

  const expectedOrder = <String>[
    'globalSetting',
    'overview',
    'point',
    'withdraw',
    'chatMonitor',
    'roomMonitor',
    'roomSessions',
    'dummy',
    'contact',
    'device',
    'deleted',
    'attribution',
    'story',
    'timeline',
    'docs',
    'moderation',
    'kyc',
    'marketing',
  ];

  test('enum AdminMenu urutannya tetap', () {
    final m = RegExp(r'enum AdminMenu \{([\s\S]*?)\n\}').firstMatch(src);
    expect(m, isNotNull, reason: 'enum AdminMenu tidak ditemukan');
    final values = RegExp(r'^\s*([a-zA-Z]+),', multiLine: true)
        .allMatches(m!.group(1)!)
        .map((e) => e.group(1)!)
        .toList();
    expect(values, expectedOrder);
  });

  for (final fn in [
    'adminMenuLabel',
    'adminMenuIcon',
    'adminMenuCategory',
    'adminMenuBody',
  ]) {
    test('setiap menu punya arm di $fn', () {
      final block = _switchBlock(src, fn);
      for (final name in expectedOrder) {
        expect(
          block.contains('AdminMenu.$name =>'),
          isTrue,
          reason: '$fn tidak punya arm untuk $name',
        );
      }
    });
  }

  test('timeline → AdminTimelineTab, docs → AdminDocsTab', () {
    final block = _switchBlock(src, 'adminMenuBody');
    expect(block.contains('AdminMenu.timeline => const AdminTimelineTab()'),
        isTrue);
    expect(block.contains('AdminMenu.docs => const AdminDocsTab()'), isTrue);
  });

  test('setiap menu tampil tepat sekali di layout, di kategori yang benar',
      () {
    final layoutStart = src.indexOf('adminMenuLayout = {');
    final layoutEnd = src.indexOf('\n};', layoutStart);
    final layout = src.substring(layoutStart, layoutEnd);
    final catBlock = _switchBlock(src, 'adminMenuCategory');
    final sections = RegExp(
      r'AdminMenuCategory\.(\w+): \[([\s\S]*?)\]',
    ).allMatches(layout).toList();
    expect(sections.length, 5, reason: 'harus 5 kategori');
    final seen = <String>[];
    for (final sec in sections) {
      final cat = sec.group(1)!;
      final menus = RegExp(r'AdminMenu\.(\w+)')
          .allMatches(sec.group(2)!)
          .map((e) => e.group(1)!)
          .toList();
      expect(menus, isNotEmpty, reason: 'kategori $cat kosong');
      for (final m in menus) {
        expect(
          catBlock.contains('AdminMenu.$m => AdminMenuCategory.$cat'),
          isTrue,
          reason: '$m ditaruh di $cat tapi adminMenuCategory berkata lain',
        );
      }
      seen.addAll(menus);
    }
    expect(seen.toSet().length, seen.length, reason: 'ada menu dobel');
    expect(seen.toSet(), expectedOrder.toSet(),
        reason: 'ada menu yang tidak tampil di halaman utama');
  });
}

/// Ambil isi `switch (m) {` pada fungsi [fn] sampai penutup `};`.
String _switchBlock(String src, String fn) {
  final idx = src.indexOf(' $fn(');
  expect(idx, greaterThanOrEqualTo(0), reason: '$fn tidak ditemukan');
  final switchIdx = src.indexOf('switch (m) {', idx);
  expect(switchIdx, greaterThanOrEqualTo(0),
      reason: '$fn tidak memakai switch(m)');
  final end = src.indexOf('\n    };', switchIdx);
  expect(end, greaterThan(switchIdx), reason: 'penutup switch $fn hilang');
  return src.substring(switchIdx, end);
}
