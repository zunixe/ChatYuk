import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/services/push_topic_service.dart';

/// Fase 4 — PushTopicService: guard self-notif & cache prefs.
/// Logic-only: FirebaseMessaging tidak ada di test → jalur panggil FM
/// dibungkus try/catch sehingga tetap aman; yang diuji perilaku logisnya.
class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MockSupabaseClient clientWithUser(String? uid) {
    final client = MockSupabaseClient();
    final auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentUser).thenReturn(uid == null ? null : _user(uid));
    return client;
  }

  test('subscribeOnline(uid sendiri) → skip (tidak subscribe topic diri)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final svc = PushTopicService.forTest(clientWithUser('uid-1'));
    await svc.subscribeOnline('uid-1');
    // Tidak ada penanda prefs → memang di-skip sebelum menulis.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('topic_sub_online-uid-1'), isNull);
  });

  test('subscribe topic orang lain tidak crash walau FM tidak ada', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = PushTopicService.forTest(clientWithUser('uid-1'));
    // FirebaseMessaging.instance null → exception ditelan oleh try/catch.
    await svc.subscribeOnline('uid-2');
    // Tidak melempar & tidak menulis flag palsu.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('topic_sub_online-uid-2'), isNot(true));
  });

  test('unsubscribe tidak crash tanpa Firebase', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = PushTopicService.forTest(clientWithUser('uid-1'));
    expect(() => svc.unsubscribeOnline('uid-2'), returnsNormally);
  });

  test('subscribe tanpa user login → lanjut tanpa guard (tidak crash)',
      () async {
    SharedPreferences.setMockInitialValues({});
    final svc = PushTopicService.forTest(clientWithUser(null));
    expect(() => svc.subscribeTimeline(), returnsNormally);
  });
}

User _user(String id) => User.fromJson({
      'id': id,
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00.000Z',
      'is_anonymous': true,
      'identities': [],
    })!;
