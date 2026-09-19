import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/avatar_service.dart';
import 'package:chatyuk/services/call_service.dart';
import 'package:chatyuk/services/device_info_service.dart';
import 'package:chatyuk/services/message_reaction_service.dart';
import 'package:chatyuk/services/private_room_service.dart';
import 'package:chatyuk/services/push_topic_service.dart';
import 'package:chatyuk/services/realtime_hub.dart';
import 'package:chatyuk/services/room_service.dart';
import 'package:chatyuk/services/storage_photo_service.dart';

import 'supabase_test_client.dart';

/// Bukti DI service singleton (Grup A): setiap service bisa dibangun dengan
/// client palsu lewat `forTest`, dan `overrideInstance`/`restoreInstance`
/// mengganti singleton untuk test tanpa merusak produksi.
void main() {
  group('forTest membangun service dengan client palsu', () {
    test('MessageReactionService', () {
      expect(MessageReactionService.forTest(fakeSupabaseClient()), isNotNull);
    });
    test('StoragePhotoService', () {
      expect(StoragePhotoService.forTest(fakeSupabaseClient()), isNotNull);
    });
    test('DeviceInfoService', () {
      expect(DeviceInfoService.forTest(fakeSupabaseClient()), isNotNull);
    });
    test('CallService', () {
      expect(CallService.forTest(fakeSupabaseClient()), isNotNull);
    });
    test('AvatarB64Service', () {
      expect(AvatarB64Service.forTest(fakeSupabaseClient()), isNotNull);
    });
    test('PrivateRoomService', () {
      expect(PrivateRoomService.forTest(fakeSupabaseClient()), isNotNull);
    });
    test('RealtimeHub', () {
      expect(RealtimeHub.forTest(fakeSupabaseClient()), isNotNull);
    });
    test('PushTopicService', () {
      expect(PushTopicService.forTest(fakeSupabaseClient()), isNotNull);
    });
    test('RoomService (ctor client opsional)', () {
      expect(RoomService(fakeSupabaseClient()), isNotNull);
      expect(RoomService(), isNotNull);
    });
  });

  group('overrideInstance mengganti singleton + restoreInstance memulihkan',
      () {
    test('MessageReactionService', () {
      final original = MessageReactionService.instance;
      final fake = MessageReactionService.forTest(fakeSupabaseClient());
      MessageReactionService.overrideInstance(fake);
      expect(identical(MessageReactionService.instance, fake), isTrue);
      MessageReactionService.restoreInstance();
      expect(identical(MessageReactionService.instance, original), isFalse);
    });

    test('avatar: non-avatar string tidak dianggap path (murni)', () {
      final svc = AvatarB64Service.forTest(fakeSupabaseClient());
      expect(svc, isNotNull);
    });

    test('StoragePhotoService.isPath (murni, tanpa I/O)', () {
      final svc = StoragePhotoService.forTest(fakeSupabaseClient());
      expect(svc.isPath('chat/x/y.jpg'), isTrue);
      expect(svc.isPath('bukan-path'), isFalse);
    });

    test('StoragePhotoService.isVoicePath (murni)', () {
      final svc = StoragePhotoService.forTest(fakeSupabaseClient());
      expect(svc.isVoicePath('voice/x.m4a'), isTrue);
      expect(svc.isVoicePath('chat/x.jpg'), isFalse);
    });
  });

  group('pure getter tidak menyentuh jaringan', () {
    test('CallService.uid null tanpa sesi', () {
      final svc = CallService.forTest(fakeSupabaseClient());
      expect(svc.uid, isNull);
    });

    test('PrivateRoomService.uid null tanpa sesi', () {
      final svc = PrivateRoomService.forTest(fakeSupabaseClient());
      expect(svc.uid, isNull);
    });
  });
}
