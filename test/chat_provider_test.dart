import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/chat_provider.dart';
import 'package:chatyuk/services/chat_service.dart'
    show ChatService, PrivateChatInfo;

class MockChatService extends Mock implements ChatService {}

PrivateChatInfo _chat(
  String id, {
  Map<String, int> unread = const {},
}) =>
    PrivateChatInfo(
      chatId: id,
      participants: const ['u1', 'u2'],
      participantNames: const {'u1': 'A', 'u2': 'B'},
      lastMessage: 'hi',
      lastMessageAt: DateTime.utc(2026, 1, 1),
      unreadCounts: unread,
    );

void main() {
  late MockChatService service;
  late ChatProvider provider;

  setUp(() {
    service = MockChatService();
    provider = ChatProvider(service: service);
  });

  group('delegasi pin/mute/archive', () {
    test('muteChat teruskan argumen + myUid ke service', () async {
      when(() => service.mutePrivateChat(any(), any(),
          myUidParam: any(named: 'myUidParam'))).thenAnswer((_) async {});
      await provider.muteChat('c1', true, myUid: 'u1');
      verify(() =>
              service.mutePrivateChat('c1', true, myUidParam: 'u1'))
          .called(1);
    });

    test('archiveChat teruskan argumen unarchive', () async {
      when(() => service.archivePrivateChat(any(), any(),
          myUidParam: any(named: 'myUidParam'))).thenAnswer((_) async {});
      await provider.archiveChat('c1', false, myUid: 'u1');
      verify(() =>
              service.archivePrivateChat('c1', false, myUidParam: 'u1'))
          .called(1);
    });

    test('pinChat teruskan argumen', () async {
      when(() => service.pinPrivateChat(any(), any(),
          myUidParam: any(named: 'myUidParam'))).thenAnswer((_) async {});
      await provider.pinChat('c1', true, myUid: 'u1');
      verify(() =>
              service.pinPrivateChat('c1', true, myUidParam: 'u1'))
          .called(1);
    });
  });

  group('hapus pesan', () {
    test('deletePrivateMessage teruskan ke service + return hasil', () async {
      when(() => service.deletePrivateMessage(any()))
          .thenAnswer((_) async => true);
      final ok = await provider.deletePrivateMessage('m1');
      expect(ok, isTrue);
      verify(() => service.deletePrivateMessage('m1')).called(1);
    });

    test('deletePrivateMessage gagal → return false', () async {
      when(() => service.deletePrivateMessage(any()))
          .thenAnswer((_) async => false);
      final ok = await provider.deletePrivateMessage('m2');
      expect(ok, isFalse);
    });
  });

  group('block list', () {
    test('loadBlockedUids mengisi + isBlocked akurat', () async {
      when(() => service.getBlockedUids('u1'))
          .thenAnswer((_) async => ['u2', 'u3']);
      await provider.loadBlockedUids('u1');
      expect(provider.isBlocked('u2'), isTrue);
      expect(provider.isBlocked('u3'), isTrue);
      expect(provider.isBlocked('u9'), isFalse);
    });
  });

  group('markAllChatsRead', () {
    test('hanya chat ber-unread yang di-mark + return jumlah', () async {
      when(() => service.lastPrivateChatsSnapshot('u1')).thenReturn([
        _chat('c1', unread: {'u1': 3}),
        _chat('c2', unread: {'u1': 0}),
        _chat('c3', unread: {'u1': 1}),
      ]);
      when(() => service.markAsRead(any(), any()))
          .thenAnswer((_) async {});
      final n = await provider.markAllChatsRead('u1');
      expect(n, 2);
      verify(() => service.markAsRead('c1', 'u1')).called(1);
      verify(() => service.markAsRead('c3', 'u1')).called(1);
      verifyNever(() => service.markAsRead('c2', 'u1'));
    });

    test('semua sudah 0 → return 0 tanpa network call', () async {
      when(() => service.lastPrivateChatsSnapshot('u1'))
          .thenReturn([_chat('c1')]);
      final n = await provider.markAllChatsRead('u1');
      expect(n, 0);
      verifyNever(() => service.markAsRead(any(), any()));
    });
  });
}
