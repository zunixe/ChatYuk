import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/providers/riverpod/missions_provider.dart';

import 'supabase_test_client.dart';
import 'test_helper.dart';

Map<String, dynamic> _anonSession(String uid) => {
      'access_token': 'anon-access',
      'refresh_token': 'anon-refresh',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': uid,
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00.000Z',
        'is_anonymous': true,
        'identities': [],
      },
    };

Map<String, dynamic> _mission(String key, {int target = 3, int progress = 0}) => {
      'id': 1,
      'mission_key': key,
      'title': 'Misi $key',
      'description': 'desc',
      'category': 'daily',
      'target_value': target,
      'target_unit': 'x',
      'reward_coins': 10,
      'is_daily': true,
      'is_locked': false,
      'progress': progress,
      'is_completed': false,
      'claimed': false,
    };

Map<String, dynamic> _missionsResp({
  String gender = 'male',
  int streak = 2,
  String? lastDate = '2026-10-31',
}) => {
      'main': [_mission('match_calls', target: 3, progress: 1)],
      'daily': [_mission('daily_signin', target: 1)],
      'total_coins': 0,
      'login_streak': streak,
      'last_login_date': lastDate,
      'gender': gender,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initSupabaseForTest();
  });

  ProviderContainer container(SupabaseClient client) => ProviderContainer(
        overrides: [missionsProvider.overrideWith(() => MissionsNotifier(client))],
      );

  group('MissionsNotifier', () {
    test('tanpa session → loading false', () {
      final c = container(fakeSupabaseClient());
      addTearDown(c.dispose);
      expect(c.read(missionsProvider).loading, false);
    });

    test('get_user_missions → state terisi (misi + streak + gender)', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/signup', (_) => _anonSession('uid-mis'));
      handler.on('get_user_missions', (_) => _missionsResp());
      handler.on('check_user_total_coins', (_) => {'total_coins': 1500});
      final client = fakeSupabaseClient(handler: handler);
      await client.auth.signInAnonymously();

      final c = container(client);
      addTearDown(c.dispose);
      c.read(missionsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final st = c.read(missionsProvider);
      expect(st.loading, false);
      expect(st.mainMissions.length, 1);
      expect(st.mainMissions.first.missionKey, 'match_calls');
      expect(st.mainMissions.first.progress, 1);
      expect(st.dailyMissions.length, 1);
      expect(st.loginStreak, 2);
      expect(st.lastLoginDate, '2026-10-31');
      expect(st.gender, 'male');
      expect(st.totalCoins, 1500);
    });

    test('updateProgress → RPC update_mission_progress + refresh', () async {
      var updateCalls = 0;
      final handler = FakeSupabaseHandler();
      handler.on('/signup', (_) => _anonSession('uid-mis'));
      handler.on('get_user_missions', (_) => _missionsResp());
      handler.on('check_user_total_coins', (_) => {'total_coins': 0});
      handler.on('update_mission_progress', (req) {
        updateCalls++;
        return {'ok': true};
      });
      final client = fakeSupabaseClient(handler: handler);
      await client.auth.signInAnonymously();

      final c = container(client);
      addTearDown(c.dispose);
      c.read(missionsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      await c.read(missionsProvider.notifier).updateProgress('chat_sent');
      expect(updateCalls, 1);
      final req = handler.captured
          .lastWhere((r) => r.url.path.contains('update_mission_progress'));
      expect(req.body, contains('chat_sent'));
    });

    test('claimReward sukses → true + state dimuat ulang', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/signup', (_) => _anonSession('uid-mis'));
      handler.on('get_user_missions', (_) => _missionsResp());
      handler.on('check_user_total_coins', (_) => {'total_coins': 0});
      handler.on('claim_mission_reward', (_) => {'success': true});
      final client = fakeSupabaseClient(handler: handler);
      await client.auth.signInAnonymously();

      final c = container(client);
      addTearDown(c.dispose);
      c.read(missionsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final ok = await c.read(missionsProvider.notifier).claimReward('match_calls');
      expect(ok, true);
    });

    test('claimReward gagal → false, tanpa throw', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/signup', (_) => _anonSession('uid-mis'));
      handler.on('get_user_missions', (_) => _missionsResp());
      handler.on('check_user_total_coins', (_) => {'total_coins': 0});
      handler.on('claim_mission_reward', (_) => {'success': false, 'error': 'nope'});
      final client = fakeSupabaseClient(handler: handler);
      await client.auth.signInAnonymously();

      final c = container(client);
      addTearDown(c.dispose);
      c.read(missionsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final ok = await c.read(missionsProvider.notifier).claimReward('match_calls');
      expect(ok, false);
    });

    test('tanpa session → claimReward/updateProgress early-return', () async {
      final c = container(fakeSupabaseClient());
      addTearDown(c.dispose);
      c.read(missionsProvider);
      final ok = await c.read(missionsProvider.notifier).claimReward('x');
      expect(ok, false);
      // Tidak throw meski tanpa session.
      await c.read(missionsProvider.notifier).updateProgress('x');
    });
  });
}
