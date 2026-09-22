import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/services/message_reaction_service.dart';

import 'supabase_test_client.dart';

/// Fase 3 — MessageReactionService: toggle/remove/fetch reaksi.
/// Logic-only: HTTP palsu; auth di-mock untuk mengontrol currentUser.
class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  group('tanpa user login (guard)', () {
    late MessageReactionService svc;

    setUp(() {
      final client = MockSupabaseClient();
      final auth = MockGoTrueClient();
      when(() => client.auth).thenReturn(auth);
      when(() => auth.currentUser).thenReturn(null);
      svc = MessageReactionService.forTest(client);
    });

    test('toggleReaction → failed saat belum login', () async {
      final r = await svc.toggleReaction(
        chatType: 'private',
        chatId: 'c1',
        messageId: 'm1',
        emoji: '❤️',
      );
      expect(r, ToggleResult.failed);
    });

    test('toggleReaction → failed untuk id pending-*', () async {
      // Bahkan dengan user, id pending ditolak (pesan belum terkirim).
      final client = MockSupabaseClient();
      final auth = MockGoTrueClient();
      when(() => client.auth).thenReturn(auth);
      when(() => auth.currentUser)
          .thenReturn(_user());
      final s = MessageReactionService.forTest(client);
      final r = await s.toggleReaction(
        chatType: 'private',
        chatId: 'c1',
        messageId: 'pending-123',
        emoji: '❤️',
      );
      expect(r, ToggleResult.failed);
    });

    test('removeReaction → false saat belum login', () async {
      expect(
        await svc.removeReaction(
          chatType: 'private',
          messageId: 'm1',
          emoji: '❤️',
        ),
        isFalse,
      );
    });
  });

  group('fetchReactors / fetchNicknames (HTTP palsu)', () {
    late MessageReactionService svc;
    late FakeSupabaseHandler handler;

    setUp(() {
      handler = FakeSupabaseHandler();
      svc = MessageReactionService.forTest(fakeSupabaseClient(handler: handler));
    });

    test('fetchReactors → map userId/emoji yang valid', () async {
      handler.on('message_reactions', (_) => [
            {'user_id': 'u1', 'emoji': '❤️', 'created_at': '2026-01-01'},
            {'user_id': '', 'emoji': '👍', 'created_at': '2026-01-02'}, // skip
          ]);
      final out = await svc.fetchReactors(
        chatType: 'private',
        messageId: 'm1',
      );
      expect(out.length, 1);
      expect(out.first['userId'], 'u1');
    });

    test('fetchReactors error → []', () async {
      final h = FakeSupabaseHandler()
        ..on('message_reactions', (_) => throw Exception('x'));
      final s = MessageReactionService.forTest(fakeSupabaseClient(handler: h));
      expect(
        await s.fetchReactors(chatType: 'private', messageId: 'm1'),
        isEmpty,
      );
    });

    test('fetchNicknames → {} bila uids kosong', () async {
      expect(await svc.fetchNicknames({}), isEmpty);
    });

    test('fetchNicknames → map id→nickname', () async {
      handler.on('profiles', (_) => [
            {'id': 'u1', 'nickname': 'Budi'},
          ]);
      final out = await svc.fetchNicknames({'u1'});
      expect(out['u1'], 'Budi');
    });
  });
}

User _user() => User.fromJson({
      'id': 'uid-1',
      'aud': 'authenticated',
      'created_at': '2026-01-01T00:00:00.000Z',
      'is_anonymous': true,
      'identities': [],
    })!;
