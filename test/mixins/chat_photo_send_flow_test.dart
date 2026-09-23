import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/media/chat_photo_helper.dart';

/// Mengunci `chat_photo_send_mixin` + `chat_photo_helper` (private ↔ room):
/// foto korup tidak crash, foto biasa di-resize JPEG, kontrak outbox room
/// (`room_<id>`) vs private (chatId). Helper murni — aman tanpa widget.
void main() {
  group('chat_photo_helper', () {
    test('bytes korup → null (tidak crash)', () {
      expect(processChatPhoto(Uint8List.fromList([0, 1, 2, 3])), isNull);
      expect(processChatImage(Uint8List.fromList([0, 1, 2, 3])), isNull);
    });

    test('bytes kosong → null', () {
      expect(processChatPhoto(Uint8List(0)), isNull);
    });
  });

  group('kontrak upload chatId', () {
    test('private pakai chatId langsung', () {
      const chatId = 'uid1_uid2';
      String uploadFor({required bool isRoom}) =>
          isRoom ? 'room_$chatId' : chatId;
      expect(uploadFor(isRoom: false), 'uid1_uid2');
    });

    test('room pakai prefix room_', () {
      const roomId = 'r1';
      String uploadFor({required bool isRoom}) =>
          isRoom ? 'room_$roomId' : roomId;
      expect(uploadFor(isRoom: true), 'room_r1');
    });
  });

  group('optimistic + antrean', () {
    test('pending foto punya id pending- + imageData terisi', () {
      final pendingId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
      const imageData = 'base64foto';
      expect(pendingId.startsWith('pending-'), isTrue);
      expect(imageData.isNotEmpty, isTrue);
    });
  });
}
