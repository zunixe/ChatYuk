import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/providers/admin_provider.dart';
import 'package:chatyuk/services/admin_service.dart';

/// Organisasi monitor chat admin: PIN + KATEGORI (folder).
/// Murni sisi klien (SharedPreferences) — tak menyentuh DB.
class MockAdminService extends Mock implements AdminService {}

void main() {
  late AdminProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = AdminProvider(service: MockAdminService());
  });

  tearDown(() => provider.dispose());

  test('mulai kosong', () async {
    await provider.loadChatOrg();
    expect(provider.isChatPinned('c1'), isFalse);
    expect(provider.chatCategoryOf('c1'), isNull);
    expect(provider.chatCategories, isEmpty);
    expect(provider.activeChatCategory, isNull);
  });

  test('toggle pin bolak-balik', () async {
    expect(await provider.toggleChatPin('c1'), isTrue);
    expect(provider.isChatPinned('c1'), isTrue);
    expect(await provider.toggleChatPin('c1'), isFalse);
    expect(provider.isChatPinned('c1'), isFalse);
  });

  test('set kategori + otomatis terdaftar di daftar kategori', () async {
    await provider.setChatCategory('c1', 'Penting');
    expect(provider.chatCategoryOf('c1'), 'Penting');
    expect(provider.chatCategories, contains('Penting'));
  });

  test('set kategori null → keluar dari kategori', () async {
    await provider.setChatCategory('c1', 'Penting');
    await provider.setChatCategory('c1', null);
    expect(provider.chatCategoryOf('c1'), isNull);
    // Nama kategori tetap ada (folder tidak terhapus otomatis).
    expect(provider.chatCategories, contains('Penting'));
  });

  test('hapus kategori → chat di dalamnya lepas', () async {
    await provider.setChatCategory('c1', 'Kerja');
    await provider.setChatCategory('c2', 'Kerja');
    await provider.removeChatCategory('Kerja');
    expect(provider.chatCategories, isNot(contains('Kerja')));
    expect(provider.chatCategoryOf('c1'), isNull);
    expect(provider.chatCategoryOf('c2'), isNull);
  });

  test('rename kategori → chat ikut pindah', () async {
    await provider.setChatCategory('c1', 'Kerja');
    await provider.renameChatCategory('Kerja', 'Kantor');
    expect(provider.chatCategories, contains('Kantor'));
    expect(provider.chatCategories, isNot(contains('Kerja')));
    expect(provider.chatCategoryOf('c1'), 'Kantor');
  });

  test('filter kategori aktif berubah', () async {
    provider.setActiveChatCategory('X');
    expect(provider.activeChatCategory, 'X');
    provider.setActiveChatCategory(null);
    expect(provider.activeChatCategory, isNull);
  });

  test('persist antar instance (SharedPreferences)', () async {
    await provider.toggleChatPin('c1');
    await provider.setChatCategory('c1', 'Penting');

    // Instance baru membaca state yang sama dari prefs.
    final p2 = AdminProvider(service: MockAdminService());
    addTearDown(p2.dispose);
    await p2.loadChatOrg();
    expect(p2.isChatPinned('c1'), isTrue);
    expect(p2.chatCategoryOf('c1'), 'Penting');
    expect(p2.chatCategories, contains('Penting'));
  });

  test('removeChatCategory saat kategori aktif → filter kembali Semua',
      () async {
    await provider.setChatCategory('c1', 'Kerja');
    provider.setActiveChatCategory('Kerja');
    await provider.removeChatCategory('Kerja');
    expect(provider.activeChatCategory, isNull);
  });

  test('filter aktif ikut berubah saat rename', () async {
    await provider.setChatCategory('c1', 'Kerja');
    provider.setActiveChatCategory('Kerja');
    await provider.renameChatCategory('Kerja', 'Kantor');
    expect(provider.activeChatCategory, 'Kantor');
  });
}
