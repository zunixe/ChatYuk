import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/services/chat_service.dart';
import 'package:chatyuk/services/room_service.dart';

import 'supabase_test_client.dart';

/// Semi-integrasi jalur **ekonomi & chat list** (HTTP palsu): memverifikasi
/// nama RPC + params yang benar-benar dikirim. Jalur koin kritikal (server
/// memotong saldo) tidak boleh salah param tanpa ketahuan.
void main() {
  // `mutePrivateChat` menyentuh NotificationPrefsService (SharedPreferences)
  // → binding test + prefs di-mock.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  group('ChatService gift/coin (I/O palsu)', () {
    test('sendCoins: p_chat_id/p_receiver_id/p_amount terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/send_coins',
        (_) => {'ok': true, 'points': 90},
      );
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      final res = await svc.sendCoins('chat-1', 'u-2', 10);

      expect(res['ok'], isTrue);
      final p = rpcParamsOf(handler, 'send_coins');
      expect(p['p_chat_id'], 'chat-1');
      expect(p['p_receiver_id'], 'u-2');
      expect(p['p_amount'], 10);
    });

    test('sendGift: p_gift_id terkirim + parsing net/cut', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/send_gift',
        (_) => {'ok': true, 'points': 50, 'net': 45, 'cut': 5},
      );
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      final res = await svc.sendGift('chat-1', 'u-2', 'rose');

      expect(res['net'], 45);
      expect(res['cut'], 5);
      final p = rpcParamsOf(handler, 'send_gift');
      expect(p['p_gift_id'], 'rose');
      expect(p['p_receiver_id'], 'u-2');
    });
  });

  group('ChatService chat-list RPC (I/O palsu)', () {
    test('markAsRead: p_chat_id + p_uid terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/mark_chat_read', (_) => []);
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      await svc.markAsRead('chat-9', 'u-1');

      final p = rpcParamsOf(handler, 'mark_chat_read');
      expect(p['p_chat_id'], 'chat-9');
      expect(p['p_uid'], 'u-1');
    });

    test('pinPrivateChat: p_chat_id + p_pin terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/pin_private_chat', (_) => []);
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      await svc.pinPrivateChat('chat-3', true, myUidParam: 'u-1');

      final p = rpcParamsOf(handler, 'pin_private_chat');
      expect(p['p_chat_id'], 'chat-3');
      expect(p['p_pin'], true);
    });

    test('mutePrivateChat: p_chat_id + p_mute terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/mute_private_chat', (_) => []);
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      await svc.mutePrivateChat('chat-4', false, myUidParam: 'u-1');

      final p = rpcParamsOf(handler, 'mute_private_chat');
      expect(p['p_chat_id'], 'chat-4');
      expect(p['p_mute'], false);
    });
  });

  group('RoomService private room (I/O palsu)', () {
    test('createPrivateRoom: nama/ikon/country/password terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/create_private_room',
        (_) => {'ok': true, 'room_id': 'pr_1'},
      );
      final svc = RoomService(fakeSupabaseClient(handler: handler));

      final res = await svc.createPrivateRoom(
        name: 'Rapat',
        icon: '💬',
        country: 'Indonesia',
        password: '1234',
      );

      expect(res['room_id'], 'pr_1');
      final p = rpcParamsOf(handler, 'create_private_room');
      expect(p['p_name'], 'Rapat');
      expect(p['p_icon'], '💬');
      expect(p['p_country'], 'Indonesia');
      expect(p['p_password'], '1234');
    });

    test('joinPrivateRoom: p_room_id + p_password terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/join_private_room',
        (_) => {'ok': true, 'charged': 5, 'points': 95},
      );
      final svc = RoomService(fakeSupabaseClient(handler: handler));

      final res = await svc.joinPrivateRoom('pr_1', password: 'abcd');

      expect(res['charged'], 5);
      final p = rpcParamsOf(handler, 'join_private_room');
      expect(p['p_room_id'], 'pr_1');
      expect(p['p_password'], 'abcd');
    });

    test('createPrivateRoom tanpa password: p_password null dikirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/create_private_room',
        (_) => {'ok': true, 'room_id': 'pr_2'},
      );
      final svc = RoomService(fakeSupabaseClient(handler: handler));

      await svc.createPrivateRoom(
        name: 'Publik',
        icon: '🌐',
        country: 'Indonesia',
      );

      final p = rpcParamsOf(handler, 'create_private_room');
      expect(p.containsKey('p_password'), isTrue);
      expect(p['p_password'], isNull);
    });
  });
}
