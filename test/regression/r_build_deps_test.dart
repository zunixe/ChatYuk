import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// REGRESSION (2026-09-19): dev-dependency `integration_test` menghasilkan
/// entri plugin di `GeneratedPluginRegistrant.java` build RELEASE, padahal
/// Gradle release tidak menyertakannya →
/// `package dev.flutter.plugins.integration_test does not exist` → BUILD
/// RELEASE GAGAL. Dev-dep mati itu sudah dihapus.
///
/// Kontrak yang dikunci: `pubspec.yaml` TIDAK boleh punya dev-dep
/// `integration_test`.
void main() {
  test('pubspec tidak memuat dev-dep integration_test (anti gagal build)',
      () {
    final src = File('pubspec.yaml').readAsStringSync();

    // Hanya cek blok dev_dependencies (bukan komentar penjelasan).
    final devIdx = src.indexOf('dev_dependencies:');
    expect(devIdx, greaterThan(-1), reason: 'blok dev_dependencies hilang');
    final devBlock = src.substring(devIdx);

    // Cari baris deklarasi (bukan komentar).
    final declares = devBlock
        .split('\n')
        .map((l) => l.trim())
        .where((l) => !l.startsWith('#'))
        .any((l) => l == 'integration_test:' || l.startsWith('integration_test:'));

    expect(declares, isFalse,
        reason: 'dev-dep integration_test memicu gagal build release '
            '(plugin bocor ke GeneratedPluginRegistrant release)');
  });

  test('folder integration_test hanya berisi README (tidak ada runner)',
      () {
    final dir = Directory('integration_test');
    if (!dir.existsSync()) return; // aman bila tidak ada
    final runners = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_test.dart'))
        .toList();
    expect(runners, isEmpty,
        reason: 'runner di integration_test/ memaksa build APK device '
            'dan gagal tanpa emulator + flavor dev yang sah');
  });
}
