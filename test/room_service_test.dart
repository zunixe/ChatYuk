import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/room_service.dart';

import 'supabase_test_client.dart';

/// Fase 4 — RoomService: RPC + PostgREST (tanpa jaringan).
/// Logic-only.
void main() {
  late FakeSupabaseHandler handler;
  late RoomService svc;

  setUp(() {
    handler = FakeSupabaseHandler();
    svc = RoomService(fakeSupabaseClient(handler: handler));
  });

  group('seedCountryRooms', () {
    test('country kosong → tidak RPC', () async {
      await svc.seedCountryRooms('');
      expect(handler.captured.isEmpty, isTrue);
    });

    test('seed memanggil RPC seed_rooms dengan p_country', () async {
      handler.on('seed_rooms', (_) => {});
      await svc.seedCountryRooms('ID');
      final p = rpcParamsOf(handler, 'seed_rooms');
      expect(p['p_country'], 'ID');
    });

    test('seed negara SAMA kedua kali → tidak RPC lagi (cache sesi)',
        () async {
      handler.on('seed_rooms', (_) => {});
      await svc.seedCountryRooms('SG_UNIQUE');
      final first = handler.captured.length;
      await svc.seedCountryRooms('SG_UNIQUE');
      expect(handler.captured.length, first); // tidak ada request baru
    });
  });

  group('fetchRooms', () {
    test('filter is_private=false & map ke RoomModel', () async {
      // fetchRooms memanggil seed dulu (RPC) lalu SELECT rooms.
      handler.on('rooms', (_) => [
            {
              'id': 'r1',
              'name': 'Umum',
              'country': 'id_test',
              'is_private': false,
              'order': 1,
            }
          ]);
      final rooms = await svc.fetchRooms('id_test');
      expect(rooms.length, 1);
      expect(rooms.first.id, 'r1');
      final req = handler.captured.firstWhere(
        (r) => r.method == 'GET' && r.url.path.contains('/rest/v1/rooms'),
      );
      expect(req.url.query.contains('is_private=eq.false'), isTrue);
      expect(req.url.query.contains('country=eq.id_test'), isTrue);
    });
  });

  group('fetchPrivateRooms', () {
    test('filter is_private=true & expires_at', () async {
      handler.on('rooms', (_) => [
            {
              'id': 'p1',
              'name': 'Grup',
              'country': 'idp',
              'is_private': true,
            }
          ]);
      final rooms = await svc.fetchPrivateRooms('idp');
      expect(rooms.length, 1);
      final req = handler.captured.firstWhere(
        (r) => r.method == 'GET' && r.url.path.contains('/rest/v1/rooms'),
      );
      expect(req.url.query.contains('is_private=eq.true'), isTrue);
    });
  });

  group('fetchMyMemberships', () {
    test('map room_id → Set', () async {
      handler.on('room_members', (_) => [
            {'room_id': 'a'},
            {'room_id': 'b'},
          ]);
      expect(await svc.fetchMyMemberships('u1'), {'a', 'b'});
    });

    test('error → {} (tidak crash)', () async {
      final h = FakeSupabaseHandler()
        ..on('room_members', (_) => throw Exception('x'));
      final s = RoomService(fakeSupabaseClient(handler: h));
      expect(await s.fetchMyMemberships('u1'), isEmpty);
    });
  });

  group('private room RPC', () {
    test('createPrivateRoom → params lengkap', () async {
      handler.on('create_private_room', (_) => {'id': 'new1', 'points': 10});
      final res = await svc.createPrivateRoom(
        name: 'Grup',
        icon: '🎧',
        country: 'ID',
        password: 'secret',
      );
      expect(res['id'], 'new1');
      final p = rpcParamsOf(handler, 'create_private_room');
      expect(p['p_name'], 'Grup');
      expect(p['p_icon'], '🎧');
      expect(p['p_country'], 'ID');
      expect(p['p_password'], 'secret');
    });

    test('joinPrivateRoom → params p_room_id + p_password', () async {
      handler.on('join_private_room', (_) => {'ok': true, 'charged': 5});
      final res = await svc.joinPrivateRoom('r1', password: 'pw');
      expect(res['ok'], true);
      final p = rpcParamsOf(handler, 'join_private_room');
      expect(p['p_room_id'], 'r1');
      expect(p['p_password'], 'pw');
    });

    test('extendRoom → params p_room_id', () async {
      handler.on('extend_private_room', (_) => {'ok': true});
      await svc.extendRoom('r1');
      expect(rpcParamsOf(handler, 'extend_private_room')['p_room_id'], 'r1');
    });

    test('deleteRoom → RPC delete_private_room', () async {
      handler.on('delete_private_room', (_) => {});
      await svc.deleteRoom('r1');
      expect(rpcParamsOf(handler, 'delete_private_room')['p_room_id'], 'r1');
    });

    test('resetRoomPassword → params p_new_password', () async {
      handler.on('reset_room_password', (_) => {'ok': true});
      await svc.resetRoomPassword('r1', 'baru');
      expect(rpcParamsOf(handler, 'reset_room_password')['p_new_password'], 'baru');
    });
  });

  group('cleanupExpired', () {
    test('panggil RPC cleanup_expired_rooms', () async {
      handler.on('cleanup_expired_rooms', (_) => {});
      await svc.cleanupExpired();
      rpcRequestOf(handler, 'cleanup_expired_rooms');
    });

    test('error → ditelan (tidak crash)', () async {
      final h = FakeSupabaseHandler()
        ..on('cleanup_expired_rooms', (_) => throw Exception('x'));
      final s = RoomService(fakeSupabaseClient(handler: h));
      expect(() => s.cleanupExpired(), returnsNormally);
    });
  });
}
