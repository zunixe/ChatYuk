import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/storage_photo_service.dart';

import 'supabase_test_client.dart';

/// Kontrak path Storage (prefix bucket + ekstensi): salah prefix/ekstensi
/// = isPath/isRoomIconPath false = foto tidak ke-load / salah render.
void main() {
  late StoragePhotoService svc;

  setUp(() {
    svc = StoragePhotoService.forTest(fakeSupabaseClientNoTicker());
  });

  group('builder path', () {
    test('avatarPath stabil (tanpa timestamp)', () {
      expect(svc.avatarPath('u1'), 'avatars/u1.jpg');
    });

    test('newPath/photoPath/postImagePath/voicePath unik + prefix benar',
        () {
      expect(svc.newPath('c1'), startsWith('chat/c1/'));
      expect(svc.newPath('c1'), endsWith('.jpg'));
      expect(svc.newPath('c1') != svc.newPath('c1'), isTrue);

      expect(svc.photoPath('u1'), startsWith('gallery/u1/'));
      expect(svc.postImagePath('u1'), startsWith('posts/u1/'));
      expect(svc.voicePath('c1'), startsWith('voice/c1/'));
      expect(svc.voicePath('c1'), endsWith('.m4a'));
      expect(svc.roomIconPath('u1'), startsWith('room-icons/u1/'));
      expect(
        svc.avatarPathVersioned('u1', ext: 'webp'),
        contains('.webp'),
      );
    });
  });

  group('predikat path', () {
    test('isPath true untuk semua prefix valid', () {
      for (final p in [
        'chat/c/x.jpg',
        'posts/u/x.png',
        'timeline/u/x.jpeg',
        'voice/c/x.m4a',
        'story/u/x.jpg',
        // webp SENGAJA tidak didukung isPath (hanya isRoomIconPath).
        'room-icons/u/x.png',
      ]) {
        expect(svc.isPath(p), isTrue, reason: p);
      }
    });

    test('isPath false untuk base64 / path asing / tanpa ekstensi', () {
      expect(svc.isPath('/9j/abc'), isFalse);
      expect(svc.isPath('avatars/u1.jpg'), isFalse);
      expect(svc.isPath('chat/c/tanpa-ekstensi'), isFalse);
      expect(svc.isPath(''), isFalse);
    });

    test('isRoomIconPath hanya room-icons + gambar', () {
      expect(svc.isRoomIconPath('room-icons/u/x.png'), isTrue);
      expect(svc.isRoomIconPath('room-icons/u/x.m4a'), isFalse);
      expect(svc.isRoomIconPath('chat/c/x.png'), isFalse);
    });

    test('isVoicePath hanya voice m4a', () {
      expect(svc.isVoicePath('voice/c/x.m4a'), isTrue);
      expect(svc.isVoicePath('voice/c/x.mp3'), isFalse);
      expect(svc.isVoicePath('chat/c/x.m4a'), isFalse);
    });
  });
}
