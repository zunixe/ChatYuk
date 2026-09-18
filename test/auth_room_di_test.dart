import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/auth_provider.dart';
import 'package:chatyuk/providers/room_provider.dart';
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

  group('AuthProvider DI', () {
    test('injeksi service + skip autoInit aman', () async {
      final auth = AuthProvider(
        authService: MockAuthService(),
        autoInit: false,
      );
      expect(auth.profile, isNull);
      expect(auth.loading, isTrue);
      expect(auth.isDeviceExcluded(null), isFalse);
      expect(auth.isDeviceExcluded(''), isFalse);
      expect(auth.isDeviceExcluded('unknown-id'), isFalse);
      await auth.setPendingReferrer('');
      auth.dispose();
    });

    test('konstruktor default tetap ada (produksi)', () {
      expect(AuthProvider.new, isNotNull);
    });
  });

  group('RoomProvider DI', () {
    test('injeksi service + skip autoInit aman', () async {
      final rooms = RoomProvider(
        service: MockRoomService(),
        chatService: MockChatService(),
        autoInit: false,
      );
      expect(rooms.rooms, isEmpty);
      expect(rooms.privateRooms, isEmpty);
      expect(rooms.myGroups, isEmpty);
      expect(rooms.country, 'Indonesia');
      expect(rooms.hasLoaded, isFalse);
      // Tanpa user login -> uid null -> return dini, tanpa network.
      await rooms.loadMyGroups();
      rooms.dispose();
    });

    test('konstruktor default tetap ada (produksi)', () {
      expect(RoomProvider.new, isNotNull);
    });
  });
}
