import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/storage_photo_service.dart';

import 'supabase_test_client.dart';

/// Fase 4 — StoragePhotoService: predikat path murni (tanpa network).
/// Ini penting: pemanggil memakai isPath untuk membedakan "base64" vs
/// "path storage" — salah klasifikasi = foto rusak.
void main() {
  late StoragePhotoService svc;

  setUp(() {
    svc = StoragePhotoService.forTest(fakeSupabaseClient());
  });

  group('isPath', () {
    test('chat/ dengan ekstensi gambar → true', () {
      expect(svc.isPath('chat/u1/abc.jpg'), isTrue);
      expect(svc.isPath('chat/u1/abc.png'), isTrue);
      expect(svc.isPath('chat/u1/abc.jpeg'), isTrue);
    });

    test('posts/ & timeline/ → true', () {
      expect(svc.isPath('posts/u1/x.jpg'), isTrue);
      expect(svc.isPath('timeline/u1/x.jpg'), isTrue);
    });

    test('story/ → true (fix: dulu tidak dikenal)', () {
      expect(svc.isPath('story/u1/a.jpg'), isTrue);
      expect(svc.isPath('story/u1/a.png'), isTrue);
    });

    test('voice/ .m4a / .mp3 → true', () {
      expect(svc.isPath('voice/u1/v.m4a'), isTrue);
      expect(svc.isPath('voice/u1/v.mp3'), isTrue);
    });

    test('prefix tanpa ekstensi → false', () {
      expect(svc.isPath('chat/u1/abc'), isFalse);
    });

    test('ekstensi tanpa prefix dikenal → false', () {
      expect(svc.isPath('other/x.jpg'), isFalse);
      expect(svc.isPath('avatars/u1/x.jpg'), isFalse);
    });

    test('base64 panjang (bukan path) → false', () {
      expect(svc.isPath('/9j/4AAQSkZJRg=='), isFalse);
    });

    test('string kosong → false', () {
      expect(svc.isPath(''), isFalse);
    });
  });

  group('isVoicePath', () {
    test('voice/ + .m4a → true', () {
      expect(svc.isVoicePath('voice/u1/v.m4a'), isTrue);
    });

    test('voice/ tanpa .m4a → false', () {
      expect(svc.isVoicePath('voice/u1/v.mp3'), isFalse);
    });

    test('bukan voice/ → false', () {
      expect(svc.isVoicePath('chat/u1/v.m4a'), isFalse);
    });
  });

  group('isAvatarPath / isGalleryPath', () {
    test('avatars/ → true', () {
      expect(svc.isAvatarPath('avatars/u1/x.jpg'), isTrue);
      expect(svc.isAvatarPath('chat/u1/x.jpg'), isFalse);
    });

    test('gallery/ → true', () {
      expect(svc.isGalleryPath('gallery/u1/x.jpg'), isTrue);
      expect(svc.isGalleryPath('avatars/u1/x.jpg'), isFalse);
    });
  });

  group('isStoryPath', () {
    test('story/ → true', () {
      expect(svc.isStoryPath('story/u1/a.jpg'), isTrue);
      expect(svc.isStoryPath('chat/u1/a.jpg'), isFalse);
      expect(svc.isStoryPath(''), isFalse);
    });

    test('storyPath() menghasilkan prefix story/<uid>/', () {
      expect(svc.storyPath('u1'), startsWith('story/u1/'));
    });
  });
}
