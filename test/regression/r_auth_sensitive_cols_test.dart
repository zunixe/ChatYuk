import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:chatyuk/providers/auth_provider.dart';
import 'package:chatyuk/services/auth_service.dart';

import '../supabase_test_client.dart';
import '../test_helper.dart';

/// REGRESSION (docs/MIGRATION_LOG.md 2026-09-21):
/// `security_hardening` mencabut SELECT level-tabel `profiles` untuk kolom
/// sensitif (email/ip_address/fcm_token/lat/lon). PostgREST `upsert`
/// (ON CONFLICT DO UPDATE) butuh SELECT pada kolom yang DITULIS → upsert
/// yang menyertakan kolom sensitif gagal `42501 permission denied`, dan
/// SEMUA pendaftaran (anon/Google/email) ikut gagal.
///
/// Kontrak yang dikunci: kolom sensitif TIDAK boleh ikut di payload upsert;
/// harus lewat `PATCH` (update) terpisah.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
  });

  /// Handler: auth signup → session; PostgREST → [].
  FakeSupabaseHandler buildHandler() {
    final h = FakeSupabaseHandler();
    // Auth signup (dipakai signInAnonymously) — pola Supabase GoTrue.
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

  test('registerProfile: upsert TANPA kolom sensitif (anti 42501)', () async {
    final handler = buildHandler();
    handler.on('/rest/v1/profiles', (_) => <dynamic>[]);

    final svc = AuthService.forTest(fakeSupabaseClient(handler: handler));
    await svc.registerProfile(
      nickname: 'Pendaftar',
      gender: 'male',
      age: 21,
      country: 'Indonesia',
      city: 'Jakarta',
    );

    final upsert = handler.captured.firstWhere(
      (r) => r.method == 'POST' && r.url.path.endsWith('/rest/v1/profiles'),
      orElse: () => throw StateError(
        'upsert profiles tidak terkirim. Requests: '
        '${handler.captured.map((r) => '${r.method} ${r.url.path}').toList()}',
      ),
    );
    final body = jsonDecode(upsert.body) as Map<String, dynamic>;

    expect(body.containsKey('email'), isFalse, reason: 'email di upsert → 42501');
    expect(body.containsKey('fcm_token'), isFalse, reason: 'fcm di upsert → 42501');
    expect(body.containsKey('ip_address'), isFalse, reason: 'ip di upsert → 42501');
    // Kolom publik tetap ada.
    expect(body['nickname'], 'Pendaftar');
    expect(body['id'], 'uid-1');
  });

  test('registerProfile: kolom sensitif dikirim via PATCH terpisah', () async {
    final handler = buildHandler();
    handler.on('/rest/v1/profiles', (_) => <dynamic>[]);

    final svc = AuthService.forTest(fakeSupabaseClient(handler: handler));
    await svc.registerProfile(
      nickname: 'Pendaftar',
      gender: 'male',
      age: 21,
      country: 'Indonesia',
      city: 'Jakarta',
    );

    final patch = handler.captured.firstWhere(
      (r) => r.method == 'PATCH' && r.url.path.endsWith('/rest/v1/profiles'),
      orElse: () => throw StateError(
        'PATCH profiles tidak terkirim — kolom sensitif tidak ditulis. '
        'Requests: ${handler.captured.map((r) => '${r.method} ${r.url.path}').toList()}',
      ),
    );
    final body = jsonDecode(patch.body) as Map<String, dynamic>;
    expect(body.containsKey('fcm_token'), isTrue,
        reason: 'fcm_token harus via PATCH, bukan upsert');
  });

  test('Provider tidak lagi hardcode service (DI tetap ada)', () {
    final svc = AuthService.forTest(fakeSupabaseClient(handler: buildHandler()));
    final provider = AuthProvider(authService: svc, autoInit: false);
    expect(provider, isNotNull);
    provider.dispose();
  });
}
