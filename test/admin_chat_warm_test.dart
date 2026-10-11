import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/admin_provider.dart';
import 'package:chatyuk/services/admin_service.dart';

class MockAdminService extends Mock implements AdminService {}

/// Pemanasan daftar monitor WAJIB lokal-saja (tanpa RPC).
///
/// Regresi keluhan "klik tampil datanya lama": itemBuilder daftar dulu memakai
/// `prefetchChatMessages` yang jatuh ke `getChatMessages` bila disk kosong →
/// buka daftar = belasan RPC bersamaan → server antre → tap ikut nunggu.
/// `warmChatMessagesLocal` hanya baca disk → memori; server diambil lazy 1×
/// saat chat dibuka.
void main() {
  late MockAdminService service;
  late AdminProvider provider;

  setUp(() {
    service = MockAdminService();
    when(
      () => service.getChatMessages(
        any(),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((_) async => <Map<String, dynamic>>[]);
    provider = AdminProvider(service: service);
  });

  tearDown(() => provider.dispose());

  test('warmChatMessagesLocal tidak menembak server', () async {
    provider.warmChatMessagesLocal('chatHangat1');
    // Beri kesempatan future background jalan (disk kosong di test env).
    await Future<void>.delayed(const Duration(milliseconds: 300));
    verifyNever(
      () => service.getChatMessages(
        any(),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    );
  });

  test('warmChatMessagesLocal id kosong → diam, tanpa RPC', () async {
    provider.warmChatMessagesLocal('');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    verifyNever(
      () => service.getChatMessages(
        any(),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    );
  });
}
