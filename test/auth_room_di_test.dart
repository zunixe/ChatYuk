import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/providers/riverpod/room_provider.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/services/room_service.dart';
import 'package:chatyuk/services/chat_service.dart';

import 'test_helper.dart';

class MockAuthService extends Mock implements AuthService {}

class MockRoomService extends Mock implements RoomService {}

class MockChatService extends Mock implements ChatService {}

void main() {
  setUpAll(() async {
    await initSupabaseForTest();
  });

  group('AuthNotifier DI', () {
    test('injeksi service + skip autoInit aman', () async {
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            () => AuthNotifier(authService: MockAuthService(), autoInit: false),
          ),
        ],
      );
      addTearDown(container.dispose);
      final auth = container.read(authProvider.notifier);
      expect(auth.profile, isNull);
      expect(auth.loading, isTrue);
      expect(auth.isDeviceExcluded(null), isFalse);
      expect(auth.isDeviceExcluded(''), isFalse);
      expect(auth.isDeviceExcluded('unknown-id'), isFalse);
      await auth.setPendingReferrer('');
    });

    test('konstruktor default tetap ada (produksi)', () {
      expect(AuthNotifier.new, isNotNull);
    });
  });

  group('RoomNotifier DI', () {
    test('injeksi service + skip autoInit aman', () async {
      final container = ProviderContainer(
        overrides: [
          roomProvider.overrideWith(
            () => RoomNotifier(
              service: MockRoomService(),
              chatService: MockChatService(),
              autoInit: false,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final rooms = container.read(roomProvider.notifier);
      expect(rooms.rooms, isEmpty);
      expect(rooms.privateRooms, isEmpty);
      expect(rooms.myGroups, isEmpty);
      expect(rooms.country, 'Indonesia');
      expect(rooms.hasLoaded, isFalse);
      // Tanpa user login -> uid null -> return dini, tanpa network.
      await rooms.loadMyGroups();
    });

    test('konstruktor default tetap ada (produksi)', () {
      expect(RoomNotifier.new, isNotNull);
    });
  });
}
