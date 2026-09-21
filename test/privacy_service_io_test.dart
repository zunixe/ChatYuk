import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:chatyuk/models/privacy_settings.dart';
import 'package:chatyuk/services/privacy_service.dart';

import 'supabase_test_client.dart';

/// Semi-integrasi `PrivacyService` dengan `SupabaseClient` asli + HTTP palsu:
/// membuktikan NAMA RPC + PARAMS yang dikirim benar (bukan sekadar "tidak
/// crash"). Semua nilai return di-stub agar jalur parsing juga teruji.
void main() {
  /// Handler auth GoTrue → memberi sesi (dibutuhkan `friends()`).
  FakeSupabaseHandler authedHandler() {
    final h = FakeSupabaseHandler();
    h.on('/auth/v1/', (req) => http.Response(
          jsonEncode({
            'access_token': 'a',
            'refresh_token': 'r',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': 'uid-1',
              'aud': 'authenticated',
              'created_at': '2026-01-01T00:00:00.000Z',
              'is_anonymous': true,
              'identities': <dynamic>[],
            },
          }),
          200,
          request: req,
          headers: {'content-type': 'application/json'},
        ));
    return h;
  }

  group('PrivacyService (I/O palsu)', () {
    test('fetch: RPC my_privacy_settings tanpa params + parsing penuh',
        () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/my_privacy_settings', (_) => {
            'presence': 'friends',
            'last_seen': 'friends_except',
            'profile_photo': 'nobody',
            'about': 'everyone',
            'story': 'friends',
            'read_receipts': false,
            'exclusions': {
              'last_seen': ['u1', 'u2'],
            },
          });
      final svc = PrivacyService(fakeSupabaseClient(handler: handler));

      final res = await svc.fetch();

      expect(res.presence, PrivacyVisibility.friends);
      expect(res.lastSeen, PrivacyVisibility.friendsExcept);
      expect(res.profilePhoto, PrivacyVisibility.nobody);
      expect(res.about, PrivacyVisibility.everyone);
      expect(res.story, PrivacyVisibility.friends);
      expect(res.readReceipts, isFalse);
      expect(res.exclusions['last_seen'], {'u1', 'u2'});
      expect(rpcParamsOf(handler, 'my_privacy_settings'), isEmpty);
    });

    test('fetch: respons bukan Map → fallback default aman', () async {
      final handler = FakeSupabaseHandler();
      final svc = PrivacyService(fakeSupabaseClient(handler: handler));

      final res = await svc.fetch();

      expect(res.presence, PrivacyVisibility.everyone);
      expect(res.readReceipts, isTrue);
      expect(res.exclusions, isEmpty);
    });

    test('update: 6 param snake_case, enum pakai name, null tetap terkirim',
        () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/update_privacy_settings',
        (_) => {'presence': 'nobody', 'read_receipts': false},
      );
      final svc = PrivacyService(fakeSupabaseClient(handler: handler));

      final res = await svc.update(
        presence: PrivacyVisibility.nobody,
        readReceipts: false,
      );

      expect(res.presence, PrivacyVisibility.nobody);
      expect(res.readReceipts, isFalse);

      final params = rpcParamsOf(handler, 'update_privacy_settings');
      expect(params['p_presence'], 'nobody');
      expect(params['p_read_receipts'], isFalse);
      expect(params.containsKey('p_last_seen'), isTrue);
      expect(params['p_last_seen'], isNull);
      expect(params['p_profile_photo'], isNull);
      expect(params['p_about'], isNull);
      expect(params['p_story'], isNull);
    });

    test('replaceExclusions: p_uids terkirim sebagai List, bukan Set',
        () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/replace_privacy_exclusions',
        (_) => {
          'last_seen': 'friends_except',
          'exclusions': {
            'last_seen': ['u1'],
          },
        },
      );
      final svc = PrivacyService(fakeSupabaseClient(handler: handler));

      final res = await svc.replaceExclusions('last_seen', {'u1'});

      expect(res.exclusions['last_seen'], {'u1'});
      final params = rpcParamsOf(handler, 'replace_privacy_exclusions');
      expect(params['p_field'], 'last_seen');
      final uids = params['p_uids'];
      expect(uids, isA<List>());
      expect(uids, contains('u1'));
    });

    test('friends: RPC privacy_excludable_users + buang entri bukan Map', () async {
      final handler = authedHandler();
      handler.on('/rest/v1/rpc/privacy_excludable_users', (_) => [
            {'uid': 'u1', 'nickname': 'Budi'},
            'bukan-map',
            {'uid': 'u2', 'nickname': 'Siti'},
          ]);
      final client = fakeSupabaseClient(handler: handler);
      await client.auth.signInAnonymously();
      final svc = PrivacyService(client);

      final res = await svc.excludableUsers();

      expect(res.length, 2);
      expect(res.first['nickname'], 'Budi');
      rpcRequestOf(handler, 'privacy_excludable_users');
    });

    test('friends: tanpa sesi → kosong & RPC TIDAK dipanggil', () async {
      final handler = FakeSupabaseHandler();
      final svc = PrivacyService(fakeSupabaseClient(handler: handler));

      final res = await svc.excludableUsers();

      expect(res, isEmpty);
      expect(
        handler.captured.where((r) => r.url.path.contains('privacy_excludable_users')),
        isEmpty,
      );
    });

    test('friends: RPC gagal → kosong tanpa crash', () async {
      final handler = authedHandler();
      handler.on(
        '/rest/v1/rpc/privacy_excludable_users',
        (req) => http.Response(
          '{"message":"boom"}',
          500,
          request: req,
          headers: {'content-type': 'application/json'},
        ),
      );
      final client = fakeSupabaseClient(handler: handler);
      await client.auth.signInAnonymously();
      final svc = PrivacyService(client);

      final res = await svc.excludableUsers();

      expect(res, isEmpty);
    });
  });
}
