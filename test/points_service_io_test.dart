import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/points_service.dart';

import 'supabase_test_client.dart';

/// Semi-integrasi `PointsService` dengan `SupabaseClient` asli + HTTP palsu:
/// membuktikan NAMA RPC + PARAMS yang dikirim benar (bukan sekadar "tidak
/// crash"). Semua nilai return di-stub agar jalur parsing juga teruji.
void main() {
  group('PointsService (I/O palsu)', () {
    test('oneTimeBonus: RPC one_time_bonus + action_key/bonus', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/one_time_bonus', (_) => 999);
      final svc = PointsService(fakeSupabaseClient(handler: handler));

      final result = await svc.oneTimeBonus('online_5min', 5);

      expect(result, 999);
      final params = rpcParamsOf(handler, 'one_time_bonus');
      expect(params['action_key'], 'online_5min');
      expect(params['bonus'], 5);
    });

    test('dailyLoginBonus: RPC + parsing map', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/daily_login_bonus',
        (_) => {'points': 10, 'streak': 3, 'bonus': 5},
      );
      final svc = PointsService(fakeSupabaseClient(handler: handler));

      final res = await svc.dailyLoginBonus();

      expect(res['points'], 10);
      expect(res['streak'], 3);
      rpcRequestOf(handler, 'daily_login_bonus');
    });

    test('claimWeeklyQuest: quest_key + tz_offset_minutes terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/claim_weekly_quest',
        (_) => {'points': 20, 'claimed': true},
      );
      final svc = PointsService(fakeSupabaseClient(handler: handler));

      final res = await svc.claimWeeklyQuest('weekly_chat', 420);

      expect(res['claimed'], isTrue);
      final params = rpcParamsOf(handler, 'claim_weekly_quest');
      expect(params['quest_key'], 'weekly_chat');
      expect(params['tz_offset_minutes'], 420);
    });

    test('unlockPhoto: p_photo_id + p_mode terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/unlock_photo',
        (_) => {'ok': true, 'points': 45, 'mode': 'once'},
      );
      final svc = PointsService(fakeSupabaseClient(handler: handler));

      final res = await svc.unlockPhoto('photo-1', 'once');

      expect(res['ok'], isTrue);
      final params = rpcParamsOf(handler, 'unlock_photo');
      expect(params['p_photo_id'], 'photo-1');
      expect(params['p_mode'], 'once');
    });

    test('leaderboard offset 0: row_offset TIDAK dikirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/points_leaderboard',
        (_) => {'scope': 'weekly', 'entries': [], 'me': null},
      );
      final svc = PointsService(fakeSupabaseClient(handler: handler));

      await svc.leaderboard('weekly', limit: 50);

      final params = rpcParamsOf(handler, 'points_leaderboard');
      expect(params['scope'], 'weekly');
      expect(params['row_limit'], 50);
      expect(params.containsKey('row_offset'), isFalse);
    });

    test('leaderboard offset > 0: row_offset dikirim (kompat paginasi)', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/points_leaderboard',
        (_) => {'scope': 'weekly', 'entries': [], 'me': null},
      );
      final svc = PointsService(fakeSupabaseClient(handler: handler));

      await svc.leaderboard('weekly', limit: 50, offset: 100);

      final params = rpcParamsOf(handler, 'points_leaderboard');
      expect(params['row_offset'], 100);
    });

    test('getWallet: parsing map bucket', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/get_wallet',
        (_) => {'bonus': 10, 'earned': 90, 'total': 100},
      );
      final svc = PointsService(fakeSupabaseClient(handler: handler));

      final w = await svc.getWallet();

      expect(w['bonus'], 10);
      expect(w['earned'], 90);
      expect(w['total'], 100);
    });

    test('fetchEnabled: hanya true yang dianggap aktif', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/get_points_enabled', (_) => true);
      final svc = PointsService(fakeSupabaseClient(handler: handler));

      expect(await svc.fetchEnabled(), isTrue);
    });

    test('quests: tz_offset_minutes terkirim + default saat kosong', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/points_quests',
        (_) => {'points': 0, 'streak': 0, 'daily': [], 'weekly': []},
      );
      final svc = PointsService(fakeSupabaseClient(handler: handler));

      await svc.quests(420);

      expect(rpcParamsOf(handler, 'points_quests')['tz_offset_minutes'], 420);
    });
  });
}
