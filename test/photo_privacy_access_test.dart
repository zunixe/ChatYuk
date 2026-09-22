import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:chatyuk/services/auth_service.dart';

import 'supabase_test_client.dart';

/// Privacy hardening (2026-09-22) — bukti `getPhotos` TIDAK lagi membaca
/// `user_photos.photo` mentah (kolom sudah di-revoke dari akses publik):
///   - foto SENDIRI  → RPC `my_photos`
///   - foto ORANG LAIN → RPC `get_user_photos_access` (paywall-aware)
void main() {
  FakeSupabaseHandler authedHandler(String myUid) {
    final h = FakeSupabaseHandler();
    h.on('/auth/v1/', (req) => http.Response(
          jsonEncode({
            'access_token': 'a',
            'refresh_token': 'r',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': myUid,
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

  /// True bila ada request POST ke RPC [fn].
  bool called(FakeSupabaseHandler h, String fn) => h.captured
      .any((r) => r.url.path.contains('/rpc/$fn'));

  group('getPhotos — jalur aman (bukan tabel mentah)', () {
    test('foto sendiri → RPC my_photos, BUKAN get_user_photos_access',
        () async {
      final h = authedHandler('me-1');
      h.on('my_photos', (_) => [
            {'id': 1, 'photo': 'AAAA', 'preview': 'pp', 'created_at': '2026-01-01T00:00:00Z'},
          ]);
      final auth = AuthService.forTest(fakeSupabaseClient(handler: h));
      await auth.signInAnonymously();

      final photos = await auth.getPhotos('me-1');

      expect(photos, hasLength(1));
      expect(called(h, 'my_photos'), isTrue);
      expect(called(h, 'get_user_photos_access'), isFalse);
    });

    test('foto orang lain → RPC get_user_photos_access (paywall), BUKAN my_photos',
        () async {
      final h = authedHandler('me-1');
      h.on('get_user_photos_access', (_) => [
            {
              'id': 9,
              'unlocked': false,
              'photo': 'blur-preview',
              'preview': 'blur-preview',
              'created_at': '2026-01-01T00:00:00Z',
            },
          ]);
      final auth = AuthService.forTest(fakeSupabaseClient(handler: h));
      await auth.signInAnonymously();

      final photos = await auth.getPhotos('other-2');

      expect(photos, hasLength(1));
      expect(photos.first.unlocked, isFalse);
      expect(called(h, 'get_user_photos_access'), isTrue);
      expect(called(h, 'my_photos'), isFalse);
    });

    test('uid kosong → tidak menyentuh network', () async {
      final h = authedHandler('me-1');
      final auth = AuthService.forTest(fakeSupabaseClient(handler: h));
      await auth.signInAnonymously();
      final photos = await auth.getPhotos('');
      expect(photos, isEmpty);
      expect(called(h, 'my_photos'), isFalse);
      expect(called(h, 'get_user_photos_access'), isFalse);
    });
  });
}
