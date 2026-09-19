import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/auth_service.dart';

import 'supabase_test_client.dart';

/// Bukti DI `AuthBase`: client Supabase disuntik lewat konstruktor sehingga
/// logika berbasis sesi (uid/isSignedIn/isAnonymous) bisa diuji dengan client
/// palsu — tanpa `Supabase.instance`.
void main() {
  group('AuthBase DI', () {
    test('tanpa sesi: uid null, tidak signed-in, anonim', () {
      final svc = AuthService.forTest(fakeSupabaseClient());

      expect(svc.uid, isNull);
      expect(svc.isSignedIn, isFalse);
      expect(svc.isAnonymous, isTrue);
      expect(svc.userEmail, isNull);
      expect(svc.emailConfirmed, isFalse);
    });

    test('forTest tidak mengganti singleton produksi', () {
      final testSvc = AuthService.forTest(fakeSupabaseClient());
      expect(identical(testSvc, AuthService.instance), isFalse);
      // Singleton tetap objek yang sama antar pemanggilan (flag dummy aman).
      expect(identical(AuthService(), AuthService.instance), isTrue);
    });

    test('forTest memakai client yang disuntik (bukan client global)', () {
      final client = fakeSupabaseClient();
      final svc = AuthService.forTest(client);
      // Akses lewat getter publik membuktikan tidak ada Supabase.instance
      // yang tersentuh (test ini jalan tanpa Supabase.initialize).
      expect(svc.currentUser, isNull);
      expect(client.auth.currentUser, isNull);
    });
  });
}
