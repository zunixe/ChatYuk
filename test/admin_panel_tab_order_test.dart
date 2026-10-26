import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regresi: tab "Timeline" pernah menampilkan DOKUMENTASI karena label
/// (TabBar) dan isi (TabBarView) ditulis sebagai dua daftar terpisah dan
/// bergeser — `AdminTimelineTab` ditaruh di indeks body 13 sementara label
/// "Timeline" ada di indeks 11 (yang menampilkan `AdminDocsTab`).
///
/// Sekarang keduanya diturunkan dari SATU enum `_AdminTab` (label & body
/// via `switch`). Test ini mengunci: (1) urutan enum tetap, dan (2) setiap
/// nilai enum punya arm di `_tabLabel` DAN `_tabBody` — mustahil ada tab
/// tanpa isi atau isi yang tertukar.
void main() {
  final src = File('lib/screens/admin_panel_screen.dart').readAsStringSync();

  // Nilai enum sesuai urutan tab yang diharapkan (indeks = posisi di sini).
  const expectedOrder = <String>[
    'globalSetting',
    'overview',
    'point',
    'chatMonitor',
    'roomMonitor',
    'dummy',
    'contact',
    'device',
    'deleted',
    'attribution',
    'story',
    'timeline',
    'docs',
    'moderation',
    'marketing',
  ];

  test('enum _AdminTab urutannya tetap', () {
    final m = RegExp(r'enum _AdminTab \{([\s\S]*?)\n\}').firstMatch(src);
    expect(m, isNotNull, reason: 'enum _AdminTab tidak ditemukan');
    final body = m!.group(1)!;
    final values = RegExp(r'^\s*([a-zA-Z]+),', multiLine: true)
        .allMatches(body)
        .map((e) => e.group(1)!)
        .toList();
    expect(values, expectedOrder);
  });

  test('setiap tab punya label di _tabLabel', () {
    final labelBlock = _switchBlock(src, '_tabLabel');
    for (final name in expectedOrder) {
      expect(
        labelBlock.contains('_AdminTab.$name =>'),
        isTrue,
        reason: '_tabLabel tidak punya arm untuk $name',
      );
    }
  });

  test('setiap tab punya isi di _tabBody', () {
    final bodyBlock = _switchBlock(src, '_tabBody');
    for (final name in expectedOrder) {
      expect(
        bodyBlock.contains('_AdminTab.$name =>'),
        isTrue,
        reason: '_tabBody tidak punya arm untuk $name',
      );
    }
  });

  test('timeline memetakan ke AdminTimelineTab, docs ke AdminDocsTab', () {
    final bodyBlock = _switchBlock(src, '_tabBody');
    expect(
      bodyBlock.contains('_AdminTab.timeline => const AdminTimelineTab()'),
      isTrue,
    );
    expect(
      bodyBlock.contains('_AdminTab.docs => const AdminDocsTab()'),
      isTrue,
    );
  });
}

/// Ambil isi `switch (tab)` pada method [methodName] (sampai `};` penutup).
String _switchBlock(String src, String methodName) {
  final idx = src.indexOf('Widget $methodName') >= 0
      ? src.indexOf('Widget $methodName')
      : src.indexOf('String $methodName');
  expect(idx, greaterThanOrEqualTo(0), reason: '$methodName tidak ditemukan');
  // Cari awal `=> switch (tab) {` lalu ambil blok sampai penanda method berikut.
  final switchIdx = src.indexOf('switch (tab) {', idx);
  expect(switchIdx, greaterThanOrEqualTo(0),
      reason: '$methodName tidak memakai switch(tab)');
  final end = src.indexOf('\n      };', switchIdx);
  expect(end, greaterThan(switchIdx), reason: 'penutup switch $methodName tidak ketemu');
  return src.substring(switchIdx, end);
}
