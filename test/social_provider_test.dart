import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/providers/social_provider.dart';
import 'package:chatyuk/services/message_cache.dart';

import 'test_helper.dart';

/// Fokus: state sosial lokal (set following/friends/pending/subscribed) &
/// pemuatan dari disk cache. Service/network di lingkungan test gagal
/// senyap; yang dikunci di sini adalah state + guard-nya.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    await MessageCache.instance.clearAll();
  });

  test('state awal kosong', () {
    final p = SocialProvider();
    expect(p.isFollowing('x'), isFalse);
    expect(p.isFriend('x'), isFalse);
    expect(p.isSubscribed('x'), isFalse);
    expect(p.isPendingFriendRequest('x'), isFalse);
    expect(p.friendRequestCount, 0);
    expect(p.following, isEmpty);
    expect(p.friends, isEmpty);
    p.dispose();
  });

  test('getter mengembalikan set unmodifiable', () {
    final p = SocialProvider();
    expect(() => p.following.add('x'), throwsUnsupportedError);
    expect(() => p.friends.add('x'), throwsUnsupportedError);
    expect(() => p.subscribed.add('x'), throwsUnsupportedError);
    expect(() => p.pendingFriendRequests.add('x'), throwsUnsupportedError);
    p.dispose();
  });

  test('tanpa sesi login → set tetap kosong (guard logout)', () async {
    // Tanpa sesi, _subscribe() menjalankan cabang logout dan mengosongkan
    // state — cache disk tidak boleh membocorkan relasi akun lama.
    await MessageCache.instance.saveRawList('social_sets', [
      {
        'following': ['u1', 'u2'],
        'friends': ['u2'],
        'pending': ['u3'],
        'subscribed': ['u4'],
      },
    ]);
    final p = SocialProvider();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(p.following, isEmpty);
    expect(p.friends, isEmpty);
    expect(p.subscribed, isEmpty);
    expect(p.pendingFriendRequests, isEmpty);
    p.dispose();
  });

  test('clearAnonSocial mengosongkan state (walau service gagal senyap)',
      () async {
    final p = SocialProvider();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await p.clearAnonSocial();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(p.following, isEmpty);
    expect(p.friends, isEmpty);
    expect(p.subscribed, isEmpty);
    expect(p.pendingFriendRequests, isEmpty);
    expect(p.friendRequestCount, 0);
    p.dispose();
  });

  test('dispose tidak melempar walau stream masih aktif', () {
    final p = SocialProvider();
    expect(p.dispose, returnsNormally);
  });
}
