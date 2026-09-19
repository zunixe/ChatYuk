import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/services/points_service.dart';

import '../supabase_test_client.dart';
import '../test_helper.dart';

/// REGRESSION (2026-09-21): `.stream()` Supabase selalu `SELECT *`
/// (supabase_stream_builder.dart: `_queryBuilder.select()`), sedangkan
/// `app_shared_secret` di-revoke dari anon/authenticated oleh
/// `security_hardening` → stream gagal `42501` dan `listenResilient`
/// retry TANPA HENTI (boros baterai + log spam).
///
/// Kontrak yang dikunci: `watchGlobalSettings` & `watchEnabled` TIDAK boleh
/// memakai `.stream()` (harus polling kolom eksplisit).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
  });

  test('watchGlobalSettings: mengambil kolom eksplisit, bukan SELECT *',
      () async {
    final handler = FakeSupabaseHandler();
    handler.on('/rest/v1/app_settings', (_) => {
          'screenshot_enabled': true,
          'require_registration': false,
        });

    final svc = AuthService.forTest(fakeSupabaseClient(handler: handler));
    final row = await svc.watchGlobalSettings().first;

    expect(row, isNotNull);
    final req = handler.captured.firstWhere(
      (r) => r.url.path.contains('/rest/v1/app_settings'),
      orElse: () => throw StateError('tidak query app_settings'),
    );
    final select = req.url.queryParameters['select'] ?? '';
    // Kolom eksplisit → tidak ada bintang.
    expect(select, isNot(contains('*')),
        reason: 'SELECT * akan menyentuh app_shared_secret → 42501');
    expect(select, contains('screenshot_enabled'));
    // Bukan realtime stream (tanpa header realtime / tidak ada channel).
    expect(req.url.queryParameters['select'], isNotEmpty);
  });

  test('watchEnabled: memakai RPC get_points_enabled, bukan stream tabel',
      () async {
    final handler = FakeSupabaseHandler();
    handler.on('/rest/v1/rpc/get_points_enabled', (_) => true);

    final svc = PointsService(fakeSupabaseClient(handler: handler));
    final enabled = await svc.watchEnabled().first;

    expect(enabled, isTrue);
    final rpc = handler.captured.where(
      (r) => r.url.path.contains('/rest/v1/rpc/get_points_enabled'),
    );
    expect(rpc, isNotEmpty, reason: 'harus lewat RPC, bukan .stream()');
  });
}
