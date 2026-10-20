import 'package:chatyuk/services/chat_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'supabase_test_client.dart';

int _count(FakeSupabaseHandler h, String fn) =>
    h.captured.where((r) => r.url.path.contains(fn)).length;

void main() {
  setUp(ChatService.resetMarkReadThrottle);
  tearDown(ChatService.resetMarkReadThrottle);

  test('throttle markAsRead lintas INSTANCE berbeda (RPC bocor)', () async {
    final h1 = FakeSupabaseHandler();
    h1.on('/rest/v1/rpc/mark_chat_read', (_) => []);
    final h2 = FakeSupabaseHandler();
    h2.on('/rest/v1/rpc/mark_chat_read', (_) => []);
    // Dua instance berbeda (meniru chatProvider vs roomProvider vs notif).
    final a = ChatService(fakeSupabaseClient(handler: h1));
    final b = ChatService(fakeSupabaseClient(handler: h2));

    await a.markAsRead('chat-x', 'u1');
    // RPC dikirim di latar (fire-and-forget) → tunggu tercatat dulu.
    await waitRpc(h1, 'mark_chat_read');
    expect(ChatService.markReadThrottled('chat-x'), isTrue);
    // Instance B: chatId SAMA dalam window → HARUS di-throttle (tidak RPC).
    await b.markAsRead('chat-x', 'u1');
    expect(_count(h1, 'mark_chat_read'), 1);
    expect(_count(h2, 'mark_chat_read'), 0);
  });

  test('chatId berbeda tetap jalan (tidak saling blok)', () async {
    final h = FakeSupabaseHandler();
    h.on('/rest/v1/rpc/mark_chat_read', (_) => []);
    final a = ChatService(fakeSupabaseClient(handler: h));
    await a.markAsRead('c-1', 'u1');
    await a.markAsRead('c-2', 'u1');
    await waitRpcCount(h, 'mark_chat_read', 2);
    expect(_count(h, 'mark_chat_read'), 2);
  });
}
