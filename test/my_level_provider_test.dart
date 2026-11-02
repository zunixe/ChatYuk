import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/providers/riverpod/my_level_provider.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/services/points_service.dart';

import 'supabase_test_client.dart';
import 'test_helper.dart';

class MockPointsService extends Mock implements PointsService {}

/// PointsProvider palsu — MyLevelNotifier me-listen `p.points` (refresh
/// level saat saldo berubah); versi asli menembak RPC di test.
class _FakePoints extends PointsNotifier {
  _FakePoints() : super(service: MockPointsService());

  @override
  PointsState build() => const PointsState();
}

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

Map<String, dynamic> _levelResp() => {
      'level': 2,
      'cumulative': 2000,
      'next_level': 3,
      'next_at': 5000,
      'remaining': 3000,
      'ladder': [
        {'level': 0, 'topup_coins': 0, 'reward_coins': 0},
        {'level': 1, 'topup_coins': 700, 'reward_coins': 50},
        {'level': 2, 'topup_coins': 2000, 'reward_coins': 100},
      ],
      'just_rewarded': [
        {'level': 2, 'reward_coins': 100},
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initSupabaseForTest();
  });

  group('MyLevelState.fromJson', () {
    test('parsing lengkap', () {
      final st = MyLevelState.fromJson(_levelResp());
      expect(st.loading, false);
      expect(st.level, 2);
      expect(st.cumulative, 2000);
      expect(st.nextLevel, 3);
      expect(st.nextAt, 5000);
      expect(st.remaining, 3000);
      expect(st.ladder.length, 3);
      expect(st.ladder[1]['topup_coins'], 700);
      expect(st.justRewarded.length, 1);
      expect(st.justRewarded[0]['reward_coins'], 100);
    });

    test('level maks → next_level/next_at null (bukan throw)', () {
      final st = MyLevelState.fromJson(
        const {'level': 10, 'cumulative': 1000000, 'remaining': 0},
      );
      expect(st.level, 10);
      expect(st.nextLevel, isNull);
      expect(st.nextAt, isNull);
      expect(st.ladder, isEmpty);
    });

    test('key hilang/tipe aneh → default aman', () {
      final st = MyLevelState.fromJson(
        const {'ladder': 'bukan-list', 'just_rewarded': 7},
      );
      expect(st.level, 0);
      expect(st.ladder, isEmpty);
      expect(st.justRewarded, isEmpty);
    });

    test('copyWith hanya mengubah loading/error', () {
      final base = MyLevelState.fromJson(_levelResp());
      final next = base.copyWith(loading: true, error: 'x');
      expect(next.loading, true);
      expect(next.error, 'x');
      expect(next.level, base.level);
      expect(next.ladder.length, base.ladder.length);
    });
  });

  group('MyLevelNotifier', () {
    ProviderContainer container(SupabaseClient client) => ProviderContainer(
          overrides: [
            myLevelProvider.overrideWith(
              () => MyLevelNotifier(PointsService(client)),
            ),
            pointsProvider.overrideWith(_FakePoints.new),
          ],
        );

    test('tanpa session → loading false', () {
      final c = container(fakeSupabaseClient());
      addTearDown(c.dispose);
      expect(c.read(myLevelProvider).loading, false);
    });

    test('RPC sukses → state terisi; justRewarded → refreshWallet', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/signup', (_) => _anonSession('uid-lvl'));
      handler.on('get_my_level', (_) => _levelResp());
      // refreshWallet() → get_wallet setelah justRewarded tidak kosong.
      handler.on('get_wallet', (_) => {'bonus': 100, 'earned': 0, 'topup': 0});
      final client = fakeSupabaseClient(handler: handler);
      await client.auth.signInAnonymously();

      final c = container(client);
      addTearDown(c.dispose);
      c.read(myLevelProvider); // trigger build + _load
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final st = c.read(myLevelProvider);
      expect(st.loading, false);
      expect(st.level, 2);
      expect(st.ladder.length, 3);
      expect(st.justRewarded.length, 1);
    });

    test('RPC gagal → error disimpan, loading false', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/signup', (_) => _anonSession('uid-lvl'));
      handler.on('get_my_level', (_) => throw Exception('boom'));
      final client = fakeSupabaseClient(handler: handler);
      await client.auth.signInAnonymously();

      final c = container(client);
      addTearDown(c.dispose);
      c.read(myLevelProvider);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final st = c.read(myLevelProvider);
      expect(st.loading, false);
      expect(st.error, isNotNull);
    });
  });

  group('userLevelProvider', () {
    test('RPC gagal → 0 (fallback aman, bukan throw)', () async {
      // Supabase.instance (dummy init) → RPC ke URL palsu → error → 0.
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final v = await c.read(userLevelProvider('uid-lain').future);
      expect(v, 0);
    });
  });
}
