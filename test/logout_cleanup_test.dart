import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/core/cache/offline_outbox.dart';
import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/providers/riverpod/chat_provider.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/services/chat_service.dart';

import 'supabase_test_client.dart';
import 'test_helper.dart';

class MockAuthService extends Mock implements AuthService {}

class MockChatService extends Mock implements ChatService {}

/// ChatNotifier uji: reset() ditahan [gate] supaya terlihat apakah signOut
/// benar-benar MENUNGGU bersih-bersih selesai.
class GatedChat extends ChatNotifier {
  GatedChat(MockChatService svc, this.gate) : super(service: svc);
  final Completer<void> gate;
  bool done = false;
  @override
  Future<void> reset() async {
    await gate.future;
    done = true;
  }
}

OutboxEntry _entry(String id) => OutboxEntry(
      pendingId: id,
      kind: 'private',
      chatId: 'chat-1',
      senderId: 'akun-lama',
      senderName: 'Lama',
      senderGender: 'male',
      text: '[TEST] $id',
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'notif_enabled': false});
  });

  group('OfflineOutbox.resetForLogout', () {
    test('antrean memori akun lama kosong setelah logout', () async {
      final outbox = OfflineOutbox.instance;
      await outbox.enqueue(_entry('p1'));
      await outbox.enqueue(_entry('p2'));
      expect(outbox.all, hasLength(2));

      outbox.resetForLogout();

      expect(outbox.all, isEmpty);
      expect(outbox.contains('p1'), isFalse);
      expect(outbox.forChat('private', 'chat-1'), isEmpty);
    });
  });

  group('ChatService.clearCachedStreams', () {
    test('timer save list chat 2 dtk dibatalkan', () {
      final svc = ChatService(fakeSupabaseClient());
      svc.debugScheduleChatListSave('akun-lama');
      expect(svc.debugPendingChatListSaves, 1);

      svc.clearCachedStreams();

      expect(svc.debugPendingChatListSaves, 0);
    });
  });

  group('ChatNotifier.reset', () {
    test('mengosongkan outbox memori & bisa di-await', () async {
      final svc = MockChatService();
      when(svc.clearCachedStreams).thenReturn(null);
      final container = ProviderContainer(
        overrides: [chatProvider.overrideWith(() => ChatNotifier(service: svc))],
      );
      addTearDown(container.dispose);
      await OfflineOutbox.instance.enqueue(_entry('p3'));

      await container.read(chatProvider.notifier).reset();

      verify(svc.clearCachedStreams).called(1);
      expect(OfflineOutbox.instance.all, isEmpty);
    });
  });

  group('AuthNotifier.signOut (jalur logout terpusat)', () {
    late MockAuthService auth;
    late Completer<void> gate;
    late GatedChat chat;
    late AuthNotifier provider;
    final calls = <String>[];

    setUp(() {
      calls.clear();
      auth = MockAuthService();
      when(() => auth.dummySessionActive).thenReturn(false);
      when(() => auth.isSignedIn).thenReturn(true);
      when(() => auth.uid).thenReturn('akun-lama');
      when(() => auth.isAnonymous).thenReturn(true);
      when(() => auth.userEmail).thenReturn(null);
      when(() => auth.emailConfirmed).thenReturn(false);
      when(() => auth.hasPassword).thenReturn(false);
      when(() => auth.currentUser).thenReturn(null);
      when(() => auth.onMyProfileUpdates()).thenAnswer(
        (_) => const Stream<({UserModel model, Set<String> keys})>.empty(),
      );
      when(() => auth.goOffline()).thenAnswer((_) async {});
      when(() => auth.releaseFcmTokenForLogout()).thenAnswer((_) async {
        calls.add('releaseFcm');
      });
      when(() => auth.signOut()).thenAnswer((_) async {
        calls.add('signOut');
      });
      gate = Completer<void>();
      final svc = MockChatService();
      chat = GatedChat(svc, gate);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => AuthNotifier(authService: auth, autoInit: false),
          ),
          chatProvider.overrideWith(() => chat),
        ],
      );
      addTearDown(container.dispose);
      provider = container.read(authProvider.notifier);
    });

    test('token FCM device ini dilepas SEBELUM sesi dibuang', () async {
      gate.complete();
      await provider.signOut();
      expect(calls, ['releaseFcm', 'signOut']);
    });

    test('signOut menunggu reset chat selesai (di-await)', () async {
      var finished = false;
      final f = provider.signOut().then((_) => finished = true);
      await pumpEventQueue();
      expect(finished, isFalse, reason: 'reset chat belum selesai');
      expect(chat.done, isFalse);

      gate.complete();
      await f;
      expect(chat.done, isTrue);
      expect(finished, isTrue);
      expect(provider.signingOut, isFalse);
    });
  });
}
