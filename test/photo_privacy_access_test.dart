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

  group('unlockPhoto — paywall permanen (koin berbayar)', () {
    test('memanggil RPC unlock_photo mode perm + return remaining', () async {
      final h = authedHandler('me-1');
      h.on('unlock_photo', (req) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['p_photo_id'], 'ph-9');
        expect(body['p_mode'], 'perm');
        return {'ok': true, 'remaining': 123};
      });
      final auth = AuthService.forTest(fakeSupabaseClient(handler: h));
      await auth.signInAnonymously();

      final remaining = await auth.unlockPhoto('ph-9', 'owner-1');

      expect(remaining, 123);
      expect(called(h, 'unlock_photo'), isTrue);
    });

    test('cache galeri owner di-invalidate setelah unlock', () async {
      final h = authedHandler('me-1');
      var accessCalls = 0;
      h.on('get_user_photos_access', (_) {
        accessCalls++;
        return [
          {'id': 9, 'unlocked': true, 'photo': 'AAAA', 'preview': 'p',
           'created_at': '2026-01-01T00:00:00Z'},
        ];
      });
      h.on('unlock_photo', (_) => {'ok': true, 'remaining': 10});
      final auth = AuthService.forTest(fakeSupabaseClient(handler: h));
      await auth.signInAnonymously();

      await auth.getPhotosWithAccess('owner-1'); // isi cache
      await auth.getPhotosWithAccess('owner-1'); // hit cache
      expect(accessCalls, 1);

      await auth.unlockPhoto('9', 'owner-1');
      await auth.getPhotosWithAccess('owner-1'); // cache batal → RPC ulang
      expect(accessCalls, 2);
    });
  });
}
