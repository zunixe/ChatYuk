import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/gifts.dart';
import 'package:chatyuk/services/chat_service.dart';

import 'supabase_test_client.dart';
import 'test_helper.dart';

/// Domain gift `ChatService` — sendCoins/sendGift meneruskan params yang
/// benar ke RPC; listGifts memakai server, fallback katalog lokal saat gagal.
void main() {
  setUpAll(() async {
    await initSupabaseForTest();
  });

  test('sendCoins → RPC send_coins + params chat/receiver/amount', () async {
    final h = FakeSupabaseHandler();
    h.on('send_coins', (_) => {'ok': true, 'points': 42});
    final svc = ChatService(fakeSupabaseClient(handler: h));

    final res = await svc.sendCoins('chat-1', 'u-recv', 25);

    expect(res['ok'], true);
    expect(res['points'], 42);
    final params = rpcParamsOf(h, 'send_coins');
    expect(params['p_chat_id'], 'chat-1');
    expect(params['p_receiver_id'], 'u-recv');
    expect(params['p_amount'], 25);
  });

  test('sendGift → RPC send_gift + params gift_id', () async {
    final h = FakeSupabaseHandler();
    h.on('send_gift', (_) => {'ok': true, 'points': 10, 'net': 8, 'cut': 2});
    final svc = ChatService(fakeSupabaseClient(handler: h));

    final res = await svc.sendGift('chat-1', 'u-recv', 'rose');

    expect(res['net'], 8);
    final params = rpcParamsOf(h, 'send_gift');
    expect(params['p_gift_id'], 'rose');
  });

  test('listGifts → data server dipakai bila tersedia', () async {
    final h = FakeSupabaseHandler();
    h.on('list_gifts', (_) => [
          {'id': 'srv1', 'emoji': '🎁', 'name_id': 'A', 'name_en': 'A', 'coins': 9},
        ]);
    final svc = ChatService(fakeSupabaseClient(handler: h));

    final gifts = await svc.listGifts();
    expect(gifts.length, 1);
    expect(gifts.first['id'], 'srv1');
  });

  test('listGifts error → fallback katalog lokal', () async {
    final h = FakeSupabaseHandler();
    h.on('list_gifts', (_) => throw StateError('down'));
    final svc = ChatService(fakeSupabaseClient(handler: h));

    final gifts = await svc.listGifts();
    expect(gifts.length, kGiftCatalog.length);
    expect(gifts.first['id'], kGiftCatalog.first.id);
    expect(gifts.first['coins'], kGiftCatalog.first.coins);
  });
}
