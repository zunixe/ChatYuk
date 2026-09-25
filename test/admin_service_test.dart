import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/admin_service.dart';

import 'supabase_test_client.dart';

/// Fase 3 — AdminService: verifikasi nama RPC + bentuk params (tanpa jaringan).
/// Logic-only: tidak menyentuh realtime/plugin.
void main() {
  late FakeSupabaseHandler handler;
  late AdminService svc;

  setUp(() {
    handler = FakeSupabaseHandler();
    svc = AdminService(fakeSupabaseClient(handler: handler));
  });

  group('stats', () {
    test('getStats → RPC admin_stats', () async {
      handler.on('admin_stats', (_) => {'users': 10});
      expect((await svc.getStats())['users'], 10);
      rpcRequestOf(handler, 'admin_stats'); // tidak throw = terkirim
    });

    test('getStatsForce → RPC admin_stats_force', () async {
      handler.on('admin_stats_force', (_) => {'users': 11});
      expect((await svc.getStatsForce())['users'], 11);
    });

    test('getStatsDetail → map (fallback {} bila null)', () async {
      handler.on('admin_stats_detail', (_) => {'x': 1});
      expect((await svc.getStatsDetail())['x'], 1);
    });

    test('getStorageStats → RPC admin_storage_stats', () async {
      handler.on('admin_storage_stats', (_) => {'bytes': 123});
      expect((await svc.getStorageStats())['bytes'], 123);
    });

    test('getTableSizes → RPC admin_table_sizes + p_limit', () async {
      handler.on(
        'admin_table_sizes',
        (_) => {
          'db_bytes': 74034323,
          'tables': [
            {'schema': 'public', 'table': 'ai_reply_log'},
          ],
        },
      );
      final res = await svc.getTableSizes(limit: 10);
      expect(res['db_bytes'], 74034323);
      expect((res['tables'] as List).length, 1);
      expect(rpcParamsOf(handler, 'admin_table_sizes')['p_limit'], 10);
    });
  });

  group('points', () {
    test('massBonus → params bonus', () async {
      handler.on('admin_mass_bonus', (_) => {'ok': true});
      await svc.massBonus(100);
      expect(rpcParamsOf(handler, 'admin_mass_bonus')['bonus'], 100);
    });

    test('togglePointsSystem → RPC admin_toggle_points params enabled', () async {
      handler.on('admin_toggle_points', (_) => true);
      expect(await svc.togglePointsSystem(true), isTrue);
      expect(
        rpcParamsOf(handler, 'admin_toggle_points')['enabled'],
        true,
      );
    });

    test('updatePointSettings → params p', () async {
      handler.on('admin_update_point_settings', (_) => {'ok': true});
      await svc.updatePointSettings({'bonus': 5});
      final p = rpcParamsOf(handler, 'admin_update_point_settings')['p'];
      expect(p, {'bonus': 5});
    });

    test('getPointSettings → map', () async {
      handler.on('admin_get_point_settings', (_) => {'bonus': 5});
      expect((await svc.getPointSettings())['bonus'], 5);
    });

    test('setPrivacyBypass → RPC + params + return map', () async {
      handler.on(
        'admin_set_privacy_bypass',
        (_) => {'privacy_bypass_enabled': true},
      );
      final res = await svc.setPrivacyBypass(true);
      expect(rpcParamsOf(handler, 'admin_set_privacy_bypass')['p_enabled'], true);
      expect(res['privacy_bypass_enabled'], true);
    });
  });

  group('chats', () {
    test('listChats → RPC admin_list_chats_page + params', () async {
      handler.on('admin_list_chats_page', (_) => {'items': [], 'total': 0});
      await svc.listChats(limit: 20, offset: 40);
      final p = rpcParamsOf(handler, 'admin_list_chats_page');
      expect(p['p_limit'], 20);
      expect(p['p_offset'], 40);
    });

    test('getChatMessages → RPC admin_get_chat_messages_page → list', () async {
      handler.on('admin_get_chat_messages_page', (_) => [
            {'id': 1},
            {'id': 2},
          ]);
      final out = await svc.getChatMessages('c1');
      expect(out.length, 2);
      final p = rpcParamsOf(handler, 'admin_get_chat_messages_page');
      expect(p['p_chat_id'], 'c1');
    });

    test('deleteChat → params diteruskan', () async {
      handler.on('admin_delete_chat', (_) => {'ok': true});
      await svc.deleteChat('c1', ['u1']);
      final p = rpcParamsOf(handler, 'admin_delete_chat');
      expect(p['p_chat_id'], 'c1');
      expect(p['p_delete_user_ids'], ['u1']);
    });

    test('getMessageImage → string dari hasil', () async {
      handler.on('admin_get_message_image', (_) => 'base64xyz');
      final out = await svc.getMessageImage(7);
      expect(out, 'base64xyz');
    });
  });

  group('devices & users', () {
    test('listDevices → params limit/offset + fallback shape', () async {
      handler.on('admin_list_devices', (_) => {'items': [], 'total': 0});
      final out = await svc.listDevices(limit: 10, offset: 0);
      expect(out.containsKey('items'), isTrue);
    });

    test('getUserDetail → params p_uid', () async {
      handler.on('admin_user_detail', (_) => {'uid': 'u1'});
      await svc.getUserDetail('u1');
      expect(rpcParamsOf(handler, 'admin_user_detail')['p_uid'], 'u1');
    });

    test('deleteAnonUser → params p_uid', () async {
      handler.on('admin_delete_anon_user', (_) => {'ok': true});
      await svc.deleteAnonUser('anon1');
      expect(rpcParamsOf(handler, 'admin_delete_anon_user')['p_uid'], 'anon1');
    });

    test('forceLogout → UPDATE profiles set fcm_token=""', () async {
      handler.on('profiles', (_) => {});
      await svc.forceLogout('u9');
      final req = handler.captured.firstWhere((r) => r.method == 'PATCH');
      expect(req.url.path.contains('/rest/v1/profiles'), isTrue);
      expect(req.body.contains('""') || req.body.contains("''"), isTrue);
    });

    test('deleteArchivedUsers → DELETE deleted_users inFilter', () async {
      handler.on('deleted_users', (_) => {});
      await svc.deleteArchivedUsers(['a', 'b']);
      final req = handler.captured.firstWhere((r) => r.method == 'DELETE');
      expect(req.url.path.contains('/rest/v1/deleted_users'), isTrue);
    });
  });

  group('deleted & registrations', () {
    test('listDeleted → params', () async {
      handler.on('admin_list_deleted', (_) => {'items': [], 'total': 0});
      final out = await svc.listDeleted(limit: 5, offset: 0);
      expect(out['total'], 0);
    });

    test('getDeletedDeviceHistory → list', () async {
      handler.on('admin_deleted_device_history', (_) => [
            {'device': 'd1'}
          ]);
      final out = await svc.getDeletedDeviceHistory('budi');
      expect(out.length, 1);
      expect(
        rpcParamsOf(handler, 'admin_deleted_device_history')['p_nickname'],
        'budi',
      );
    });

    test('getDeletedLocationHistory → list', () async {
      handler.on('admin_deleted_location_history', (_) => [
            {'lat': 1.0, 'lon': 2.0}
          ]);
      final out = await svc.getDeletedLocationHistory('uid1');
      expect(out.length, 1);
      expect(
        rpcParamsOf(handler, 'admin_deleted_location_history')['p_user_id'],
        'uid1',
      );
    });

    test('listRegistrations → params + fallback shape', () async {
      handler.on('admin_registrations_list', (_) => {'items': [], 'total': 0});
      await svc.listRegistrations(limit: 15, offset: 0);
      expect(
        rpcParamsOf(handler, 'admin_registrations_list')['p_limit'],
        15,
      );
    });

    test('fetchHiddenUids → Set dari {dummy,excluded}', () async {
      handler.on('admin_hidden_uids', (_) => {
            'dummy': ['a'],
            'excluded': ['b'],
          });
      final out = await svc.fetchHiddenUids();
      expect(out, {'a', 'b'});
    });

    test('fetchHiddenUids → {} saat null', () async {
      handler.on('admin_hidden_uids', (_) => <String, dynamic>{});
      expect(await svc.fetchHiddenUids(), isEmpty);
    });
  });

  group('calls', () {
    test('getActiveCalls → parse ActiveCallInfo', () async {
      handler.on('admin_active_calls', (_) => [
            {'call_id': 'c1', 'caller_uid': 'a', 'callee_uid': 'b'},
          ]);
      final out = await svc.getActiveCalls();
      expect(out, isA<List>());
    });

    test('sweepStaleCalls → int hasil', () async {
      handler.on('admin_sweep_calls', (_) => 3);
      expect(await svc.sweepStaleCalls(), 3);
    });
  });

  group('excluded devices', () {
    test('getExcludedDevices → Set dari list', () async {
      handler.on('app_settings', (_) => {'excluded_devices': ['d1', 'd2']});
      final out = await svc.getExcludedDevices();
      expect(out, {'d1', 'd2'});
    });

    test('getExcludedDevices → {} saat error', () async {
      final h = FakeSupabaseHandler()
        ..on('app_settings', (_) => throw Exception('down'));
      final s = AdminService(fakeSupabaseClient(handler: h));
      expect(await s.getExcludedDevices(), isEmpty);
    });
  });
}
