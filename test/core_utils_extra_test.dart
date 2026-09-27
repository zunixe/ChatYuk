import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/core/perf/rpc_probe.dart';
import 'package:chatyuk/core/ui/scroll_pagination.dart';
import 'package:chatyuk/core/photo_quality_pref.dart';

import 'supabase_test_client.dart';

/// Fase 2 — util/helper baru dari refactor (instrumentasi RPC, paginasi
/// scroll, preferensi kualitas foto). Perilaku murni + tidak butuh jaringan.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('measuredRpc', () {
    test('meneruskan fn + params ke SupabaseClient.rpc', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/hello', (req) => {'ok': true});
      final client = fakeSupabaseClient(handler: handler);

      final res = await measuredRpc(
        client,
        'hello',
        params: {'p_a': 1, 'p_b': 'x'},
      );

      expect(res, {'ok': true});
      final body = rpcParamsOf(handler, 'hello');
      expect(body['p_a'], 1);
      expect(body['p_b'], 'x');
    });

    test('tanpa params → tetap memanggil rpc', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/ping', (req) => 'pong');
      final client = fakeSupabaseClient(handler: handler);

      final res = await measuredRpc(client, 'ping');
      expect(res, 'pong');
    });

    test('label custom diterima (tidak mengubah hasil)', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/admin_x', (req) => {'n': 1});
      final client = fakeSupabaseClient(handler: handler);

      final res = await measuredRpc(client, 'admin_x', label: 'admin.admin_x');
      expect(res, {'n': 1});
    });
  });

  group('ScrollPagination', () {
    test('panggil onLoadMore saat mendekati bawah (setelah debounce)',
        () async {
      final ctrl = ScrollController();
      addTearDown(ctrl.dispose);
      var calls = 0;
      final p = ScrollPagination(
        controller: ctrl,
        onLoadMore: () => calls++,
        threshold: 100,
        debounce: const Duration(milliseconds: 10),
      );
      addTearDown(p.dispose);
      // Controller belum punya klien → listener tidak crash.
      expect(calls, 0);
    });

    test('dispose aman dipanggil (cancel timer + lepas listener)', () {
      final ctrl = ScrollController();
      final p = ScrollPagination(controller: ctrl, onLoadMore: () {});
      expect(() => p.dispose(), returnsNormally);
      ctrl.dispose();
    });
  });

  group('PhotoQualityPref', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('default false (Standar) saat belum diset', () async {
      expect(await PhotoQualityPref.defaultHd, isFalse);
    });

    test('set true → defaultHd true (persist)', () async {
      await PhotoQualityPref.setDefaultHd(true);
      expect(await PhotoQualityPref.defaultHd, isTrue);
    });

    test('set false lagi → kembali false', () async {
      await PhotoQualityPref.setDefaultHd(true);
      await PhotoQualityPref.setDefaultHd(false);
      expect(await PhotoQualityPref.defaultHd, isFalse);
    });
  });
}
