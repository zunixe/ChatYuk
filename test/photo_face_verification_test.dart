import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/media/face_check.dart';
import 'package:chatyuk/core/profile/photo_verification.dart';
import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/models/user_photo.dart';

// Regresi source-level: memastikan jalur upload female selalu melewati
// validasi wajah (kalau ada yang menghapus gate ini, test gagal).
void _sourceGuards() {
  final photos = File(
    'lib/screens/profile/profile_photos.dart',
  ).readAsStringSync();
  final online = File(
    'lib/screens/online_users/widgets/avatar_upload.dart',
  ).readAsStringSync();
  final kyc = File(
    'lib/screens/kyc/kyc_selfie_camera_screen.dart',
  ).readAsStringSync();

  test('slot foto female: cek wajah langsung saat dipilih', () {
    expect(photos, contains('pickVerifiedFacePhoto'));
    expect(photos, contains('faceVerified: _isFemaleAccount'));
    // Sheet tetap menawarkan kamera + galeri (dua-duanya divalidasi).
    expect(photos, contains('s.photoVerifySheetBody'));
    expect(photos, contains('s.avatarGallery'));
  });

  test('avatar profil female: validasi pada hasil crop', () {
    final a = photos.indexOf('Future<void> _pickAndUpload(');
    expect(a, greaterThanOrEqualTo(0));
    final blok = photos.substring(a, a + 900);
    expect(blok, contains('_isFemaleAccount'));
    expect(blok, contains('pickVerifiedFacePhoto'));
    expect(blok, contains('crop:'));
  });

  test('avatar dari halaman Online ikut aturan female', () {
    expect(online, contains('requiresFaceVerifiedPhoto'));
    expect(online, contains('pickVerifiedFacePhoto'));
    expect(online, contains('faceVerified: isFemale'));
  });

  test('kamera verifikasi punya mode ketat tanpa jepret manual', () {
    expect(kyc, contains('allowManualFallback'));
    expect(kyc, contains('photoVerifyCameraFailed'));
  });
}

void main() {
  _sourceGuards();

  group('kebijakan verifikasi foto profil', () {
    test('female wajib foto wajah asli', () {
      expect(requiresFaceVerifiedPhoto('female'), isTrue);
    });

    test('male bebas (galeri/kamera biasa)', () {
      expect(requiresFaceVerifiedPhoto('male'), isFalse);
    });

    test('gender belum termuat → tidak memaksa (jangan blokir user)', () {
      expect(requiresFaceVerifiedPhoto(null), isFalse);
      expect(requiresFaceVerifiedPhoto(''), isFalse);
    });
  });

  group('FaceCheck.checkFile', () {
    test('file tidak ada / detektor gagal → failed (jangan blokir)', () async {
      final r = await FaceCheck.checkFile('/nonexistent/foto.jpg');
      expect(r, FaceCheckResult.failed);
    });
  });

  group('UserPhoto.faceVerified', () {
    test('foto baru terverifikasi', () {
      final p = UserPhoto.fromMap('1', {
        'userId': 'u',
        'photo': 'data',
        'createdAt': '2026-11-08T00:00:00Z',
        'faceVerified': true,
      });
      expect(p.faceVerified, isTrue);
    });

    test('foto lama tanpa cap → perlu diganti', () {
      final p = UserPhoto.fromMap('2', {
        'userId': 'u',
        'photo': 'data',
        'createdAt': '2026-11-08T00:00:00Z',
      });
      expect(p.faceVerified, isFalse);
    });
  });

  group('UserModel.avatarFaceVerified', () {
    test('dibaca dari key camel & snake (RPC profile_public)', () {
      final camel = UserModel.fromMap('u', {'avatarFaceVerified': true});
      expect(camel.avatarFaceVerified, isTrue);
      final snake = UserModel.fromMap('u', {'avatar_face_verified': true});
      expect(snake.avatarFaceVerified, isTrue);
    });

    test('default false (foto lama) + copyWith bisa menandai', () {
      final m = UserModel.fromMap('u', {'nickname': 'A'});
      expect(m.avatarFaceVerified, isFalse);
      expect(m.copyWith(avatarFaceVerified: true).avatarFaceVerified, isTrue);
    });
  });
}
