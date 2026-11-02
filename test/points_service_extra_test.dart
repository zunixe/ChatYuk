import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/points_service.dart';

import 'supabase_test_client.dart';
import 'test_helper.dart';

/// Semi-integrasi `PointsService` untuk method yang belum tercakup
/// `points_service_io_test.dart` — membuktikan nama RPC + params yang
/// dikirim benar lewat HTTP palsu.
void main() {
  setUpAll(() async {
    await initSupabaseForTest();
  });





  test('getUserLevel → RPC get_user_level + p_user', () async {
    final h = FakeSupabaseHandler();
    h.on('get_user_level', (_) => {'level': 3});
    final svc = PointsService(fakeSupabaseClient(handler: h));

    expect(await svc.getUserLevel('u-x'), 3);
    expect(rpcParamsOf(h, 'get_user_level')['p_user'], 'u-x');
  });



  test('pointHistory tanpa session → [] tanpa query', () async {
    final h = FakeSupabaseHandler();
    final svc = PointsService(fakeSupabaseClient(handler: h));
    expect(await svc.pointHistory(), isEmpty);
    expect(
      h.captured.where((r) => r.url.path.contains('coin_ledger')).length,
      0,
    );
  });
}
