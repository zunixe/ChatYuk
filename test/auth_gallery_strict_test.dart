import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/auth_service.dart';

import 'supabase_test_client.dart';
import 'test_helper.dart';

/// Galeri ketat: upload gagal → throw (BUKAN fallback base64 ke DB).
/// Pola: sesi anon via HTTP palsu + endpoint storage dipaksa gagal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
    await prewarmMediaForTest();
  });

  Map<String, dynamic> anonSession(String uid) => {
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

  test('upload gagal → throw upload_failed, tanpa insert', () async {
    final handler = FakeSupabaseHandler();
    // GoTrue signInAnonymously → POST /auth/v1/signup (tanpa email).
    handler.on('/signup', (_) => anonSession('uid-galeri'));
    handler.on('storage', (_) => throw Exception('storage down'));
    final client = fakeSupabaseClient(handler: handler);
    await client.auth.signInAnonymously();
    final svc = AuthService.forTest(client);

    // PNG 1px valid (lolos isValidImageBase64 + batas 1MB).
    const png1px =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    await expectLater(
      svc.uploadPhoto(png1px),
      throwsA(
        isA<Exception>().having(
          (e) => e.toString(),
          'pesan',
          contains('upload_failed'),
        ),
      ),
    );
    final inserts = handler.captured.where(
      (r) => r.method == 'POST' && r.url.path.contains('/user_photos'),
    );
    expect(inserts, isEmpty,
        reason: 'gagal upload tidak boleh insert apa pun (dulu base64)');
  });
}
