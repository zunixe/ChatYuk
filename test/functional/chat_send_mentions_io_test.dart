import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/providers/chat_provider.dart';
import 'package:chatyuk/services/chat_service.dart';
import 'package:chatyuk/utils/mention.dart';

import '../supabase_test_client.dart';

/// Functional (semi-integrasi): alur kirim pesan dari PROVIDER turun ke
/// SERVICE nyata dengan HTTP palsu — memverifikasi payload yang benar-benar
/// sampai ke PostgREST, termasuk `mentions`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('kirim room message ber-mention → payload mentions benar', () async {
    final handler = FakeSupabaseHandler();
    handler.on('/rest/v1/messages', (_) => []);
    final provider = ChatProvider(
      service: ChatService(fakeSupabaseClient(handler: handler)),
    );

    await provider.sendRoomMessage(
      roomId: 'r1',
      senderId: 'u1',
      senderName: 'Budi',
      senderGender: 'male',
      text: 'hai @Sari',
      mentions: const [Mention(uid: 'u-sari', name: 'Sari')],
    );

    final insert = handler.captured.firstWhere(
      (r) => r.method == 'POST' && r.url.path.contains('/rest/v1/messages'),
    );
    final body = jsonDecode(insert.body) as Map<String, dynamic>;
    expect(body['room_id'], 'r1');
    expect(body['text'], 'hai @Sari');
    expect(body['mentions'], [
      {'uid': 'u-sari', 'name': 'Sari'},
    ]);
    provider.dispose();
  });

  test('kirim private message ber-mention → payload + chat_id benar',
      () async {
    final handler = FakeSupabaseHandler();
    handler.on('/rest/v1/private_chats', (_) => []);
    handler.on('/rest/v1/private_messages', (_) => {'id': 7});
    final provider = ChatProvider(
      service: ChatService(fakeSupabaseClient(handler: handler)),
    );

    await provider.sendPrivateMessage(
      chatId: 'u1_u2',
      senderId: 'u1',
      senderName: 'Budi',
      senderGender: 'male',
      text: 'hai @Sari',
      mentions: const [Mention(uid: 'u-sari', name: 'Sari')],
    );

    final insert = handler.captured.firstWhere(
      (r) =>
          r.method == 'POST' &&
          r.url.path.contains('/rest/v1/private_messages'),
    );
    final body = jsonDecode(insert.body) as Map<String, dynamic>;
    expect(body['chat_id'], 'u1_u2');
    expect(body['mentions'], [
      {'uid': 'u-sari', 'name': 'Sari'},
    ]);
    provider.dispose();
  });

  test('tanpa mention → kolom mentions tidak dikirim (hemat payload)',
      () async {
    final handler = FakeSupabaseHandler();
    handler.on('/rest/v1/messages', (_) => []);
    final provider = ChatProvider(
      service: ChatService(fakeSupabaseClient(handler: handler)),
    );

    await provider.sendRoomMessage(
      roomId: 'r1',
      senderId: 'u1',
      senderName: 'Budi',
      senderGender: 'male',
      text: 'halo biasa',
    );

    final insert = handler.captured.firstWhere(
      (r) => r.method == 'POST' && r.url.path.contains('/rest/v1/messages'),
    );
    final body = jsonDecode(insert.body) as Map<String, dynamic>;
    expect(body.containsKey('mentions'), isFalse);
    provider.dispose();
  });
}
