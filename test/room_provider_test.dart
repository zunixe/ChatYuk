import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/models/room_model.dart';
import 'package:chatyuk/providers/room_provider.dart';
import 'package:chatyuk/services/chat_service.dart';
import 'package:chatyuk/services/room_service.dart';

import 'test_helper.dart';

/// Fase 3 — RoomProvider (logic-only): state room, apply counts, join/delete.
/// `autoInit: false` → tidak menyentuh RealtimeHub/Supabase saat konstruksi.
class MockRoomService extends Mock implements RoomService {}

class MockChatService extends Mock implements ChatService {}

RoomModel _room(String id, {int online = 0}) => RoomModel(
      id: id,
      name: 'Room $id',
      description: '',
      icon: '🎧',
      country: 'ID',
      category: 'general',
      order: 0,
      onlineCount: online,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockRoomService service;
  late MockChatService chat;

  setUpAll(() async {
    await initSupabaseForTest();
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    service = MockRoomService();
    chat = MockChatService();
    // Method yang dipanggil konstruktor/reload otomatis.
    when(() => service.cleanupExpired()).thenAnswer((_) async {});
    when(() => service.fetchPrivateRooms(any())).thenAnswer((_) async => []);
    when(() => service.fetchMyMemberships(any())).thenAnswer((_) async => {});
    when(() => service.watchPrivateRooms(any()))
        .thenAnswer((_) => const Stream<List<RoomModel>>.empty());
    when(() => chat.getRoomOnlineCounts(country: any(named: 'country')))
        .thenAnswer((_) => const Stream.empty());
  });

  RoomProvider make() =>
      RoomProvider(service: service, chatService: chat, autoInit: false);

  group('reload', () {
    test('sukses → rooms terisi, hasLoaded true, error null', () async {
      when(() => service.fetchRooms(any()))
          .thenAnswer((_) async => [_room('r1'), _room('r2')]);
      final p = make();
      await p.reload();
      expect(p.rooms.length, 2);
      expect(p.hasLoaded, isTrue);
      expect(p.error, isNull);
      p.dispose();
    });

    test('error → error terisi, hasLoaded tetap true (tidak crash)', () async {
      when(() => service.fetchRooms(any())).thenThrow(Exception('down'));
      final p = make();
      await p.reload();
      expect(p.error, isNotNull);
      expect(p.hasLoaded, isTrue);
      p.dispose();
    });
  });

  group('joinPrivateRoom', () {
    test('ok=true → roomId masuk memberRoomIds', () async {
      when(() => service.joinPrivateRoom(any(), password: any(named: 'password')))
          .thenAnswer((_) async => {'ok': true});
      final p = make();
      final res = await p.joinPrivateRoom('r9');
      expect(res['ok'], true);
      expect(p.memberRoomIds.contains('r9'), isTrue);
      p.dispose();
    });

    test('ok=false → memberRoomIds tidak berubah', () async {
      when(() => service.joinPrivateRoom(any(), password: any(named: 'password')))
          .thenAnswer((_) async => {'ok': false, 'reason': 'wrong_pw'});
      final p = make();
      await p.joinPrivateRoom('r9', password: 'x');
      expect(p.memberRoomIds.contains('r9'), isFalse);
      p.dispose();
    });
  });

  group('deleteRoom / extendRoom', () {
    test('deleteRoom → delegasi + reloadPrivate dipanggil', () async {
      when(() => service.deleteRoom(any())).thenAnswer((_) async {});
      final p = make();
      await p.deleteRoom('r1');
      verify(() => service.deleteRoom('r1')).called(1);
      verify(() => service.fetchPrivateRooms(any())).called(greaterThan(0));
      p.dispose();
    });

    test('extendRoom → kembalikan hasil service', () async {
      when(() => service.extendRoom(any()))
          .thenAnswer((_) async => {'ok': true, 'minutes': 30});
      final p = make();
      final res = await p.extendRoom('r1');
      expect(res['minutes'], 30);
      p.dispose();
    });
  });

  group('setCountry', () {
    test('negara sama → tidak reload', () async {
      when(() => service.fetchRooms(any()))
          .thenAnswer((_) async => [_room('r1')]);
      final p = make();
      await p.reload();
      clearInteractions(service);
      await p.setCountry(p.country); // sama → early return
      verifyNever(() => service.fetchRooms(any()));
      p.dispose();
    });

    test('negara beda → country berubah & reload', () async {
      when(() => service.fetchRooms(any()))
          .thenAnswer((_) async => [_room('r1')]);
      final p = make();
      await p.setCountry('SG');
      expect(p.country, 'SG');
      verify(() => service.fetchRooms('SG')).called(greaterThan(0));
      p.dispose();
    });
  });
}
