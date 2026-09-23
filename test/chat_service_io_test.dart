import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/chat_service.dart';
import 'package:chatyuk/utils/mention.dart';

import 'supabase_test_client.dart';

/// Test I/O service dengan `SupabaseClient` asli + HTTP palsu: membuktikan
/// payload yang dikirim `ChatService` ke PostgREST benar (tanpa jaringan).
void main() {
  group('sendRoomMessage (I/O palsu)', () {
    test('teks: insert ke tabel messages + kolom wajib', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/messages', (_) => []);
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      await svc.sendRoomMessage(
        roomId: 'r1',
        senderId: 'u1',
        senderName: 'Budi',
        senderGender: 'male',
        text: 'halo dunia',
      );

      final insert = handler.captured.firstWhere(
        (r) => r.method == 'POST' && r.url.path.contains('/rest/v1/messages'),
      );
      final body = jsonDecode(insert.body) as Map<String, dynamic>;
      expect(body['room_id'], 'r1');
      expect(body['sender_id'], 'u1');
      expect(body['text'], 'halo dunia');
      expect(body['type'], 'text');
      // Tanpa mention → kolom mentions tidak dikirim.
      expect(body.containsKey('mentions'), isFalse);
    });

    test('mention: kolom mentions terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/messages', (_) => []);
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      await svc.sendRoomMessage(
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
      expect(body['mentions'], [
        {'uid': 'u-sari', 'name': 'Sari'},
      ]);
    });

    test('tipe tidak valid → throw sebelum kirim', () async {
      final handler = FakeSupabaseHandler();
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      await expectLater(
        svc.sendRoomMessage(
          roomId: 'r1',
          senderId: 'u1',
          senderName: 'Budi',
          senderGender: 'male',
          text: 'x',
          type: 'tidak-valid',
        ),
        throwsA(isA<Exception>()),
      );
      expect(handler.captured, isEmpty);
    });

    test('teks kosong → tidak mengirim apa pun', () async {
      final handler = FakeSupabaseHandler();
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      await svc.sendRoomMessage(
        roomId: 'r1',
        senderId: 'u1',
        senderName: 'Budi',
        senderGender: 'male',
        text: '',
      );
      expect(handler.captured, isEmpty);
    });

    test('room text lebih dari 2000 karakter → error, bukan silent drop',
        () async {
      final handler = FakeSupabaseHandler();
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      await expectLater(
        svc.sendRoomMessage(
          roomId: 'r1',
          senderId: 'u1',
          senderName: 'Budi',
          senderGender: 'male',
          text: 'x' * 2001,
        ),
        throwsA(isA<Exception>()),
      );
      expect(handler.captured, isEmpty);
    });
  });

  group('sendPrivateMessage validasi (I/O palsu)', () {
    test('tipe tidak valid tidak mengirim request', () async {
      final handler = FakeSupabaseHandler();
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      await expectLater(
        svc.sendPrivateMessage(
          chatId: 'u1_u2',
          senderId: 'u1',
          senderName: 'Budi',
          senderGender: 'male',
          text: 'x',
          type: 'invalid',
        ),
        throwsA(isA<Exception>()),
      );
      expect(handler.captured, isEmpty);
    });

    test('teks lebih dari 2000 karakter tidak mengirim request', () async {
      final handler = FakeSupabaseHandler();
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      await expectLater(
        svc.sendPrivateMessage(
          chatId: 'u1_u2',
          senderId: 'u1',
          senderName: 'Budi',
          senderGender: 'male',
          text: 'x' * 2001,
        ),
        throwsA(isA<Exception>()),
      );
      expect(handler.captured, isEmpty);
    });

    test('image data invalid tidak mengirim request', () async {
      final handler = FakeSupabaseHandler();
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      await expectLater(
        svc.sendPrivateMessage(
          chatId: 'u1_u2',
          senderId: 'u1',
          senderName: 'Budi',
          senderGender: 'male',
          text: '',
          type: 'image',
          imageData: 'not-base64-or-storage-path',
        ),
        throwsA(isA<Exception>()),
      );
      expect(handler.captured, isEmpty);
    });
  });

  group('deleteRoomMessage (I/O palsu)', () {
    test('PATCH is_deleted=true ke messages', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/messages', (_) => [
        {'id': 'm1'},
      ]);
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      final ok = await svc.deleteRoomMessage('m1');

      expect(ok, isTrue);
      final patch = handler.captured.firstWhere((r) => r.method == 'PATCH');
      expect(patch.body, contains('is_deleted'));
      expect(patch.url.query, contains('id=eq.m1'));
    });

    test('0 baris ter-update (blokir RLS) → return false', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/messages', (_) => []);
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      final ok = await svc.deleteRoomMessage('m1');

      expect(ok, isFalse);
    });
  });

  group('deletePrivateMessage (I/O palsu)', () {
    test('PATCH is_deleted=true ke private_messages', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/private_messages', (_) => [
        {'id': 'm1'},
      ]);
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      final ok = await svc.deletePrivateMessage('m1');

      expect(ok, isTrue);
      final patch = handler.captured.firstWhere((r) => r.method == 'PATCH');
      expect(patch.body, contains('is_deleted'));
      expect(patch.url.query, contains('id=eq.m1'));
    });

    test('0 baris ter-update (blokir RLS) → return false', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/private_messages', (_) => []);
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      final ok = await svc.deletePrivateMessage('m1');

      expect(ok, isFalse);
    });
  });

  group('editRoomMessage (I/O palsu)', () {
    test('PATCH text + edited ke messages', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/messages', (_) => []);
      final svc = ChatService(fakeSupabaseClient(handler: handler));

      final ok = await svc.editRoomMessage('m1', 'teks baru');

      expect(ok, isTrue);
      final patch = handler.captured.firstWhere((r) => r.method == 'PATCH');
      final body = jsonDecode(patch.body) as Map<String, dynamic>;
      expect(body['text'], 'teks baru');
      expect(body['edited'], isTrue);
    });
  });
}
