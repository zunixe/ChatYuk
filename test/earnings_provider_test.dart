import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/providers/riverpod/earnings_provider.dart';

import 'supabase_test_client.dart';
import 'test_helper.dart';

/// Sesi anon palsu — `auth.currentUser` terisi setelah signInAnonymously.
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

/// Respons `get_earnings_summary` lengkap (semua field dipetakan).
Map<String, dynamic> _summary() => {
      'total_earnings': 900,
      'weekly_earnings': 300,
      'today_earnings': 40,
      'breakdown': {
        'private_call': 500,
        'match_call': 150,
        'message': 20,
        'gift': 80,
        'mission': 50,
        'bonus': 60,
        'other': 40,
      },
      'stats': {
        'video_call_count': 4,
        'video_call_seconds': 480,
        'match_call_count': 3,
        'match_call_seconds': 210,
        'avg_match_seconds': 70,
        'private_call_total': 10,
        'private_call_answered': 6,
        'private_answer_rate': 60,
      },
      'withdrawable': 700,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initSupabaseForTest();
  });

  ProviderContainer container(SupabaseClient client) => ProviderContainer(
        overrides: [earningsProvider.overrideWith(() => EarningsNotifier(client))],
      );

  group('EarningsState.fromJson', () {
    test('parsing lengkap — semua field dipetakan', () {
      final st = EarningsState.fromJson(_summary());
      expect(st.loading, false);
      expect(st.totalEarnings, 900);
      expect(st.weeklyEarnings, 300);
      expect(st.todayEarnings, 40);
      // Breakdown income.
      expect(st.privateCall, 500);
      expect(st.matchCall, 150);
      expect(st.message, 20);
      expect(st.gift, 80);
      expect(st.mission, 50);
      expect(st.bonus, 60);
      expect(st.other, 40);
      // Statistik aktivitas.
      expect(st.videoCallCount, 4);
      expect(st.videoCallSeconds, 480);
      expect(st.matchCallCount, 3);
      expect(st.matchCallSeconds, 210);
      expect(st.avgMatchSeconds, 70);
      expect(st.privateCallTotal, 10);
      expect(st.privateCallAnswered, 6);
      expect(st.privateAnswerRate, 60);
      expect(st.withdrawable, 700);
    });

    test('key hilang/kosong → default 0, tidak throw', () {
      final st = EarningsState.fromJson(const {});
      expect(st.totalEarnings, 0);
      expect(st.gift, 0);
      expect(st.privateAnswerRate, 0);
      expect(st.withdrawable, 0);
      expect(st.loading, false);
      final st2 = EarningsState.fromJson(
        const {'breakdown': 'bukan-map', 'stats': 42},
      );
      expect(st2.gift, 0);
      expect(st2.videoCallCount, 0);
    });

    test('copyWith hanya mengubah loading/error', () {
      final base = EarningsState.fromJson(_summary());
      final next = base.copyWith(loading: true, error: 'x');
      expect(next.loading, true);
      expect(next.error, 'x');
      expect(next.totalEarnings, base.totalEarnings);
      expect(next.gift, base.gift);
    });
  });

  group('EarningsNotifier', () {
    test('tanpa session → loading false, tanpa crash', () {
      final c = container(fakeSupabaseClient());
      addTearDown(c.dispose);
      final st = c.read(earningsProvider);
      expect(st.loading, false);
    });

    test('RPC sukses → state terisi penuh', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/signup', (_) => _anonSession('uid-earn'));
      handler.on('get_earnings_summary', (_) => _summary());
      final client = fakeSupabaseClient(handler: handler);
      await client.auth.signInAnonymously();

      final c = container(client);
      addTearDown(c.dispose);
      c.read(earningsProvider); // trigger build + _load
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final st = c.read(earningsProvider);
      expect(st.loading, false);
      expect(st.error, isNull);
      expect(st.totalEarnings, 900);
      expect(st.gift, 80);
      expect(st.matchCallCount, 3);
      expect(st.withdrawable, 700);
    });

    test('RPC gagal → error disimpan, loading false', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/signup', (_) => _anonSession('uid-earn'));
      handler.on('get_earnings_summary', (_) => throw Exception('boom'));
      final client = fakeSupabaseClient(handler: handler);
      await client.auth.signInAnonymously();

      final c = container(client);
      addTearDown(c.dispose);
      c.read(earningsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final st = c.read(earningsProvider);
      expect(st.loading, false);
      expect(st.error, isNotNull);
      expect(st.totalEarnings, 0);
    });
  });
}
