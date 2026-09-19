import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/providers/message_reaction_provider.dart';
import 'package:chatyuk/providers/notification_prefs_provider.dart';
import 'package:chatyuk/services/message_reaction_service.dart';

class MockMessageReactionService extends Mock
    implements MessageReactionService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MessageReactionProvider passthrough', () {
    late MockMessageReactionService service;
    late MessageReactionProvider provider;

    setUp(() {
      service = MockMessageReactionService();
      provider = MessageReactionProvider(service: service);
    });

    test('toggleReaction meneruskan semua argumen + hasil', () async {
      when(() => service.toggleReaction(
            chatType: any(named: 'chatType'),
            chatId: any(named: 'chatId'),
            messageId: any(named: 'messageId'),
            emoji: any(named: 'emoji'),
          )).thenAnswer((_) async => ToggleResult.added);

      final res = await provider.toggleReaction(
        chatType: 'private',
        chatId: 'c1',
        messageId: 'm1',
        emoji: '❤️',
      );

      expect(res, ToggleResult.added);
      verify(() => service.toggleReaction(
            chatType: 'private',
            chatId: 'c1',
            messageId: 'm1',
            emoji: '❤️',
          )).called(1);
    });

    test('removeReaction meneruskan argumen', () async {
      when(() => service.removeReaction(
            chatType: any(named: 'chatType'),
            messageId: any(named: 'messageId'),
            emoji: any(named: 'emoji'),
          )).thenAnswer((_) async => true);

      expect(
        await provider.removeReaction(
          chatType: 'room',
          messageId: 'm2',
          emoji: '👍',
        ),
        isTrue,
      );
      verify(() => service.removeReaction(
            chatType: 'room',
            messageId: 'm2',
            emoji: '👍',
          )).called(1);
    });

    test('toggleStar meneruskan argumen + hasil removed', () async {
      when(() => service.toggleStar(
            chatType: any(named: 'chatType'),
            chatId: any(named: 'chatId'),
            messageId: any(named: 'messageId'),
          )).thenAnswer((_) async => ToggleResult.removed);

      expect(
        await provider.toggleStar(
          chatType: 'private',
          chatId: 'c1',
          messageId: 'm3',
        ),
        ToggleResult.removed,
      );
    });

    test('loadCachedReactions / saveCachedReactions diteruskan', () async {
      when(() => service.loadCachedReactions('c1')).thenAnswer(
        (_) async => {
          'm1': {'❤️': 2},
        },
      );
      when(() => service.saveCachedReactions(any(), any()))
          .thenAnswer((_) async {});

      final loaded = await provider.loadCachedReactions('c1');
      expect(loaded['m1']!['❤️'], 2);

      await provider.saveCachedReactions('c1', loaded);
      verify(() => service.saveCachedReactions('c1', loaded)).called(1);
    });

    test('watchReactions / watchStarred diteruskan sebagai stream', () {
      when(() => service.watchReactions('c1'))
          .thenAnswer((_) => Stream.value(const {}));
      when(() => service.watchStarred('c1'))
          .thenAnswer((_) => Stream.value(<String>{}));

      expect(provider.watchReactions('c1'), isA<Stream>());
      expect(provider.watchStarred('c1'), isA<Stream>());
    });
  });

  group('NotificationPrefsProvider passthrough', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('setEnabled + isEnabled + allPrefs konsisten', () async {
      final p = NotificationPrefsProvider();

      // Default semua true.
      expect(await p.isEnabled('chat'), isTrue);

      await p.setEnabled('chat', false);
      expect(await p.isEnabled('chat'), isFalse);

      final all = await p.allPrefs();
      expect(all['chat'], isFalse);
      expect(all['call'], isTrue, reason: 'tipe lain tidak terpengaruh');
    });

    test('mute per-chat: set → true, unset → false', () async {
      final p = NotificationPrefsProvider();

      expect(await p.isChatMuted('chat-x'), isFalse);
      await p.setChatMuted('chat-x', true);
      expect(await p.isChatMuted('chat-x'), isTrue);
      await p.setChatMuted('chat-x', false);
      expect(await p.isChatMuted('chat-x'), isFalse);
    });
  });
}
