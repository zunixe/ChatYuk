import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/admin_service.dart';
import 'package:chatyuk/services/chat_service.dart';

import 'supabase_test_client.dart';

/// Admin hapus pesan room SIAPA PUN — verifikasi jalur RPC (tanpa jaringan).
///
/// Dua jalur klien memanggil RPC SECURITY DEFINER yang sama
/// (`admin_delete_room_message`), yang di server menegakkan gate email admin:
/// - `ChatService.adminDeleteRoomMessage` — dipakai di room chat normal
///   (long-press → Hapus oleh admin, dengan UNDO).
/// - `AdminService.adminDeleteRoomMessage` — dipakai di panel admin monitor
///   room (long-press pesan → Hapus).
///
/// Test ini mengunci NAMA RPC + bentuk params (p_message_id bigint, p_deleted
/// bool) supaya kesalahan kontrak ketahuan sebelum deploy.
void main() {
  late FakeSupabaseHandler handler;

  setUp(() {
    handler = FakeSupabaseHandler();
  });

  group('ChatService.adminDeleteRoomMessage', () {
    test('hapus → RPC admin_delete_room_message p_deleted=true', () async {
      handler.on(
        'admin_delete_room_message',
        (_) => {'ok': true, 'rows': 1},
      );
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      final ok = await svc.adminDeleteRoomMessage('123');

      expect(ok, isTrue);
      final params = rpcParamsOf(handler, 'admin_delete_room_message');
      expect(params['p_message_id'], 123); // bigint, dikonversi dari String id
      expect(params['p_deleted'], true);
    });

    test('undo → p_deleted=false', () async {
      handler.on(
        'admin_delete_room_message',
        (_) => {'ok': true, 'rows': 1},
      );
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      final ok = await svc.adminDeleteRoomMessage('456', undelete: true);

      expect(ok, isTrue);
      final params = rpcParamsOf(handler, 'admin_delete_room_message');
      expect(params['p_message_id'], 456);
      expect(params['p_deleted'], false);
    });

    test('server tolak (ok=false) → return false', () async {
      handler.on(
        'admin_delete_room_message',
        (_) => {'ok': false, 'rows': 0},
      );
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      expect(await svc.adminDeleteRoomMessage('999'), isFalse);
    });

    test('error server → return false (tidak melempar)', () async {
      // Tanpa route → handler default menjawab [] (bukan map ok=true).
      final svc = ChatService(fakeSupabaseClient(handler: handler));
      expect(await svc.adminDeleteRoomMessage('1'), isFalse);
    });
  });

  group('AdminService.adminDeleteRoomMessage', () {
    test('hapus pesan monitor → RPC + params benar', () async {
      handler.on(
        'admin_delete_room_message',
        (_) => {'ok': true, 'rows': 1},
      );
      final svc = AdminService(fakeSupabaseClient(handler: handler));

      final ok = await svc.adminDeleteRoomMessage('789');

      expect(ok, isTrue);
      final params = rpcParamsOf(handler, 'admin_delete_room_message');
      expect(params['p_message_id'], 789);
      expect(params['p_deleted'], true);
    });

    test('undo → p_deleted=false', () async {
      handler.on(
        'admin_delete_room_message',
        (_) => {'ok': true, 'rows': 1},
      );
      final svc = AdminService(fakeSupabaseClient(handler: handler));

      final ok = await svc.adminDeleteRoomMessage('790', undelete: true);

      expect(ok, isTrue);
      expect(
        rpcParamsOf(handler, 'admin_delete_room_message')['p_deleted'],
        false,
      );
    });

    test('server tolak → false', () async {
      handler.on(
        'admin_delete_room_message',
        (_) => {'ok': false, 'rows': 0},
      );
      final svc = AdminService(fakeSupabaseClient(handler: handler));

      expect(await svc.adminDeleteRoomMessage('791'), isFalse);
    });
  });
}
