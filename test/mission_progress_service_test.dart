import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/mission_progress_service.dart';

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

/// `MissionProgressService` — semua track* adalah RPC `update_mission_progress`
/// dengan `p_mission_key` yang benar; tracking misi non-kritis → error RPC
/// dilewati (bukan dilempar), dan tanpa session → early-return.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initSupabaseForTest();
  });

  Future<MissionProgressService> signedIn(FakeSupabaseHandler handler) async {
    handler.on('/signup', (_) => _anonSession('uid-mp'));
    handler.on('update_mission_progress', (_) => {'ok': true});
    final client = fakeSupabaseClient(handler: handler);
    await client.auth.signInAnonymously();
    return MissionProgressService(client: client);
  }

  /// Params RPC `update_mission_progress` yang TERAKHIR (tiap track* menembak
  /// satu RPC — `rpcParamsOf` hanya mengembalikan yang pertama).
  Map<String, dynamic> lastParams(FakeSupabaseHandler h) {
    final req = h.captured
        .where((r) => r.url.path.endsWith('/rest/v1/rpc/update_mission_progress'))
        .last;
    return (jsonDecode(req.body) as Map).cast<String, dynamic>();
  }

  String? lastKey(FakeSupabaseHandler h) =>
      lastParams(h)['p_mission_key'] as String?;

  group('pemetaan mission_key', () {
    test('updateProgress → key bebas + increment', () async {
      final h = FakeSupabaseHandler();
      final svc = await signedIn(h);
      await svc.updateProgress('custom_key', increment: 7);
      final params = rpcParamsOf(h, 'update_mission_progress');
      expect(params['p_mission_key'], 'custom_key');
      expect(params['p_increment'], 7);
    });

    test('trackOnlineMinutes/CallMinutes → daily_online_minutes/call_minutes',
        () async {
      final h = FakeSupabaseHandler();
      final svc = await signedIn(h);
      await svc.trackOnlineMinutes(3);
      expect(lastKey(h), 'daily_online_minutes');
      await svc.trackCallMinutes(2);
      expect(lastKey(h), 'call_minutes');
    });

    test('trackMatchCall/trackPrivateCall → match_calls/private_calls',
        () async {
      final h = FakeSupabaseHandler();
      final svc = await signedIn(h);
      await svc.trackMatchCall();
      expect(lastKey(h), 'match_calls');
      await svc.trackPrivateCall();
      expect(lastKey(h), 'private_calls');
    });

    test('trackMessageSent/trackGiftReceived → key yang benar', () async {
      final h = FakeSupabaseHandler();
      final svc = await signedIn(h);
      await svc.trackMessageSent();
      expect(lastKey(h), 'message_various_users');
      await svc.trackGiftReceived();
      expect(lastKey(h), 'daily_receive_gift');
    });
  });

  group('guard', () {
    test('tanpa session → tidak ada RPC & tidak throw', () async {
      final h = FakeSupabaseHandler();
      final svc = MissionProgressService(client: fakeSupabaseClient(handler: h));
      await svc.updateProgress('x');
      await svc.trackMatchCall();
      expect(h.captured.where((r) => r.url.path.contains('rpc')).length, 0);
    });

    test('RPC error → dilewati, tidak melempar', () async {
      final h = FakeSupabaseHandler();
      h.on('/signup', (_) => _anonSession('uid-mp'));
      h.on('update_mission_progress', (_) => throw StateError('boom'));
      final client = fakeSupabaseClient(handler: h);
      await client.auth.signInAnonymously();
      final svc = MissionProgressService(client: client);
      // Tidak boleh throw — tracking misi efek samping non-kritis.
      await svc.trackPrivateCall();
    });
  });
}
