import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/riverpod/social_provider.dart';
import 'package:chatyuk/services/social_service.dart';

import 'supabase_test_client.dart';

class MockSocialService extends Mock implements SocialService {}

/// SocialNotifier uji: build() hermetic (tanpa langganan realtime/auth).
class _TestSocial extends SocialNotifier {
  _TestSocial(SocialService svc)
      : super(service: svc, sb: fakeSupabaseClient());
  @override
  SocialState build() => const SocialState();
}

/// Mengunci kontrak aksi friend request di `SocialNotifier`:
/// - `sendFriendRequest` → 'pending' | 'friends' | 'failed' (JANGAN '').
/// - `respondFriendRequest` sinkron state lokal (friends/counter) setelah accept.
/// - `cancelFriendRequest` benar-benar menghapus dari set pending.
///
/// Regresi nyata (user SimpleMe "Batal gagal"): pemanggil dulu memakai
/// `res != 'rejected'` yang SELALU true → gagal pun bilang "terkirim".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSocialService svc;
  final containers = <ProviderContainer>[];

  setUp(() {
    svc = MockSocialService();
  });

  tearDown(() {
    for (final c in containers) {
      c.dispose();
    }
    containers.clear();
  });

  SocialNotifier prov() {
    final c = ProviderContainer(
      overrides: [socialProvider.overrideWith(() => _TestSocial(svc))],
    );
    containers.add(c);
    return c.read(socialProvider.notifier);
  }

  group('sendFriendRequest', () {
    test('sukses → "pending" + pending lokal di-set', () async {
      when(() => svc.sendFriendRequest('u2'))
          .thenAnswer((_) async => {'ok': true, 'status': 'pending'});
      final p = prov();
      final r = await p.sendFriendRequest('u2');
      expect(r, 'pending');
      expect(p.isPendingFriendRequest('u2'), isTrue);
      expect(p.isFriend('u2'), isFalse);
    });

    test('sudah teman → "friends" + friends lokal di-set', () async {
      when(() => svc.sendFriendRequest('u2'))
          .thenAnswer((_) async => {'ok': true, 'already_friends': true});
      final p = prov();
      final r = await p.sendFriendRequest('u2');
      expect(r, 'friends');
      expect(p.isFriend('u2'), isTrue);
      expect(p.isPendingFriendRequest('u2'), isFalse);
    });

    test('gagal (exception) → "failed" (bukan "" / bukan sukses)', () async {
      when(() => svc.sendFriendRequest('u2'))
          .thenThrow(Exception('ANON_DISABLED'));
      final p = prov();
      final r = await p.sendFriendRequest('u2');
      expect(r, 'failed');
      expect(p.isPendingFriendRequest('u2'), isFalse);
      // 'failed' != 'pending'/'friends' → UI tidak menampilkan sukses.
      expect(r == 'pending' || r == 'friends', isFalse);
    });

    test('respons server tanpa ok → "failed"', () async {
      when(() => svc.sendFriendRequest('u2'))
          .thenAnswer((_) async => {'reason': 'whatever'});
      final p = prov();
      expect(await p.sendFriendRequest('u2'), 'failed');
    });

    test('target kosong → "failed" tanpa panggil service', () async {
      final p = prov();
      expect(await p.sendFriendRequest(''), 'failed');
      verifyNever(() => svc.sendFriendRequest(any()));
    });
  });

  group('respondFriendRequest', () {
    test('accept → refresh set (friends terisi) + counter terbarui', () async {
      when(() => svc.uid).thenReturn('me');
      when(() => svc.respondFriendRequest(7, true))
          .thenAnswer((_) async => {'ok': true, 'accepted': true});
      when(() => svc.socialList(any(), any())).thenAnswer((_) async => []);
      when(() => svc.socialList('friends', any())).thenAnswer(
        (_) async => [
          {'uid': 'u-from'},
        ],
      );
      when(() => svc.mySubscriptions()).thenAnswer((_) async => []);
      when(() => svc.friendRequestOutbox()).thenAnswer((_) async => []);
      when(() => svc.friendRequestInbox()).thenAnswer((_) async => []);

      final p = prov();
      final res = await p.respondFriendRequest(7, true);
      expect(res['ok'], isTrue);
      // _refreshSelfSetsNow() jalan → friends terisi dari service.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(p.isFriend('u-from'), isTrue);
      expect(p.friendRequestCount, 0);
    });
  });

  group('cancelFriendRequest', () {
    test('ok → hapus dari set pending', () async {
      when(() => svc.sendFriendRequest('u3'))
          .thenAnswer((_) async => {'ok': true, 'status': 'pending'});
      when(() => svc.cancelFriendRequest(9)).thenAnswer((_) async => {'ok': true});
      final p = prov();
      await p.sendFriendRequest('u3');
      expect(p.isPendingFriendRequest('u3'), isTrue);
      final ok = await p.cancelFriendRequest(9, targetUid: 'u3');
      expect(ok, isTrue);
      expect(p.isPendingFriendRequest('u3'), isFalse);
    });

    test('non-pending (server ok:false) → return false, tidak ubah state',
        () async {
      when(() => svc.cancelFriendRequest(9)).thenAnswer(
        (_) async => {'ok': false, 'reason': 'not_pending'},
      );
      final p = prov();
      final ok = await p.cancelFriendRequest(9, targetUid: 'u3');
      expect(ok, isFalse);
    });
  });
}
