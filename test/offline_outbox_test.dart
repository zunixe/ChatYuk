import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/core/cache/offline_outbox.dart';

OutboxEntry _entry(
  String id, {
  String chatId = 'chat-1',
  String kind = 'private',
  DateTime? at,
}) =>
    OutboxEntry(
      pendingId: id,
      kind: kind,
      chatId: chatId,
      senderId: 'me',
      senderName: 'Aku',
      senderGender: 'male',
      text: 'halo $id',
      createdAt: at ?? DateTime.utc(2026, 1, 1, 0, 0),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('OutboxEntry serialisasi', () {
    test('toMap → fromMap roundtrip mempertahankan field penting', () {
      final e = OutboxEntry(
        pendingId: 'p1',
        kind: 'room',
        chatId: 'r9',
        senderId: 'u1',
        senderName: 'Budi',
        senderGender: 'male',
        text: 'pesan',
        type: 'image',
        imagePayload: 'base64xx',
        needsUpload: true,
        uploadKind: 'chat',
        durationMs: 4200,
        repliedToId: 'm0',
        repliedToText: 'asli',
        repliedToSenderName: 'Ani',
        isForwarded: true,
        pointsDeducted: true,
        pointsKind: 'image',
        createdAt: DateTime.utc(2026, 5, 5, 10, 30),
      );
      final back = OutboxEntry.fromMap(e.toMap());
      expect(back.pendingId, 'p1');
      expect(back.kind, 'room');
      expect(back.chatId, 'r9');
      expect(back.type, 'image');
      expect(back.needsUpload, isTrue);
      expect(back.durationMs, 4200);
      expect(back.repliedToId, 'm0');
      expect(back.isForwarded, isTrue);
      expect(back.pointsDeducted, isTrue);
      expect(back.pointsKind, 'image');
      expect(back.createdAt, DateTime.utc(2026, 5, 5, 10, 30));
    });

    test('fromMap tahan map kosong → default aman', () {
      final e = OutboxEntry.fromMap(const {});
      expect(e.pendingId, '');
      expect(e.kind, 'private');
      expect(e.type, 'text');
      expect(e.needsUpload, isFalse);
      expect(e.pointsKind, 'text');
    });
  });

  group('OfflineOutbox antrean', () {
    test('enqueue → contains true, remove → false', () async {
      final outbox = OfflineOutbox.instance;
      final id = 'unit-enqueue-${DateTime.now().microsecondsSinceEpoch}';
      await outbox.enqueue(_entry(id));
      expect(outbox.contains(id), isTrue);

      await outbox.remove(id);
      expect(outbox.contains(id), isFalse);
    });

    test('forChat memfilter per kind + chatId', () async {
      final outbox = OfflineOutbox.instance;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final chatA = 'chatA-$stamp';
      final chatB = 'chatB-$stamp';

      await outbox.enqueue(_entry('1', chatId: chatA, kind: 'private'));
      await outbox.enqueue(_entry('2', chatId: chatA, kind: 'private'));
      await outbox.enqueue(_entry('3', chatId: chatB, kind: 'private'));
      await outbox.enqueue(_entry('4', chatId: chatA, kind: 'room'));

      expect(outbox.forChat('private', chatA).length, 2);
      expect(outbox.forChat('private', chatB).length, 1);
      expect(outbox.forChat('room', chatA).length, 1);
      expect(outbox.forChat('room', chatB), isEmpty);
    });

    test('enqueue pendingId sama → tidak duplikat (replace)', () async {
      final outbox = OfflineOutbox.instance;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final chat = 'chatDup-$stamp';
      await outbox.enqueue(_entry('9', chatId: chat));
      await outbox.enqueue(_entry('9', chatId: chat));
      expect(outbox.forChat('private', chat).length, 1);
    });

    test('cap 50: enqueue 60 → semua tersimpan tepat 50 terbaru', () async {
      final outbox = OfflineOutbox.instance;
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final chat = 'chatCap-$stamp';
      final base = DateTime.utc(2026, 1, 1);
      for (var i = 0; i < 60; i++) {
        await outbox.enqueue(
          _entry('c$i', chatId: chat, at: base.add(Duration(seconds: i))),
        );
      }
      final items = outbox.forChat('private', chat);
      expect(items.length, 50, reason: 'cap maksimal 50 item');
      // Yang tertinggal harus 50 TERBARU (c10..c59), bukan yang lama.
      expect(items.any((e) => e.pendingId == 'c59'), isTrue);
      expect(items.any((e) => e.pendingId == 'c9'), isFalse);
    });
  });

  group('OutboxEntry.isNetworkError', () {
    test('gangguan jaringan dikenali', () {
      for (final msg in [
        Exception('SocketException: Failed host lookup'),
        Exception('Network is unreachable'),
        Exception('Connection refused'),
        Exception('Connection timed out'),
        Exception('ClientException with SocketException'),
        Exception('TlsException: handshake failed'),
        Exception('No internet connection'),
      ]) {
        expect(OfflineOutbox.isNetworkError(msg), isTrue, reason: '$msg');
      }
    });

    test('error non-jaringan TIDAK dikenali', () {
      for (final msg in [
        Exception('row-level security policy'),
        Exception('42501 permission denied'),
        Exception('duplicate key value violates unique constraint'),
        Exception('JWT expired'),
      ]) {
        expect(OfflineOutbox.isNetworkError(msg), isFalse, reason: '$msg');
      }
    });
  });
}
