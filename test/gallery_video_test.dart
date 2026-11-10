import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'package:chatyuk/core/media/face_check.dart';
import 'package:chatyuk/models/user_photo.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/services/storage_photo_service.dart';

import 'supabase_test_client.dart';
import 'test_helper.dart';

/// Video di "Foto Saya" (galeri profil):
///   - path/berkas video (`gallery/...mp4`) + poster pasangan `_poster.jpg`
///   - video TIDAK pernah diunduh jadi base64 (hanya poster kecilnya)
///   - female: video wajib memuat wajah (sampling frame + ML Kit)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
    await prewarmMediaForTest();
  });

  FakeSupabaseHandler authedHandler(String myUid) {
    final h = FakeSupabaseHandler();
    h.on(
      '/auth/v1/',
      (req) => http.Response(
        jsonEncode({
          'access_token': 'a',
          'refresh_token': 'r',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': myUid,
            'aud': 'authenticated',
            'created_at': '2026-01-01T00:00:00.000Z',
            'is_anonymous': true,
            'identities': <dynamic>[],
          },
        }),
        200,
        request: req,
        headers: {'content-type': 'application/json'},
      ),
    );
    return h;
  }

  bool called(FakeSupabaseHandler h, String fn) =>
      h.captured.any((r) => r.url.path.contains('/rpc/$fn'));

  group('guard source — verifikasi wajah video di LAYAR REKAM', () {
    test('female + kamera memakai kamera in-app (bukan cek luar)', () {
      final src = File(
        'lib/screens/profile/profile_photos_video.dart',
      ).readAsStringSync();
      expect(src, contains('FaceCaptureVideoScreen'));
      expect(src, contains('source != ImageSource.camera'));
    });

    test('layar rekam: deteksi live + verifikasi hasil di layar yang sama', () {
      final cam = File('lib/widgets/face_capture_video.dart').readAsStringSync();
      expect(cam, contains('FaceCheck.options'));
      // Verifikasi hasil rekaman tampil di layar rekam (spinner/pesan).
      expect(cam, contains('FaceCheck.checkVideo('));
      // Rekam TANPA frame-callback: `onAvailable` + video capture memicu
      // bug plugin camera_android_camerax #180075 — PREVIEW berputar 90°
      // ("jadi wide") selama merekam. Jangan dikembalikan.
      expect(cam, contains('startVideoRecording()'));
      expect(cam, isNot(contains('startVideoRecording(onAvailable:')));
      // Auto-stop sesuai batas durasi.
      expect(cam, contains('elapsedMilliseconds >= widget.maxMs'));
    });
  });

  group('StoragePhotoService — path video galeri', () {
    final svc = StoragePhotoService.instance;

    test('deteksi path video (mp4/mov/webm) hanya di folder gallery/', () {
      expect(svc.isGalleryVideoPath('gallery/u/1.mp4'), isTrue);
      expect(svc.isGalleryVideoPath('gallery/u/1.mov'), isTrue);
      expect(svc.isGalleryVideoPath('gallery/u/1.webm'), isTrue);
      expect(svc.isGalleryVideoPath('gallery/u/1.jpg'), isFalse);
      expect(svc.isGalleryVideoPath('story/u/1.mp4'), isFalse);
      expect(svc.isGalleryVideoPath('chat/u/1.mp4'), isFalse);
    });

    test('poster = file pasangan dari path video (kontrak upload/baca/hapus)',
        () {
      expect(
        svc.galleryPosterPath('gallery/u/123.mp4'),
        'gallery/u/123_poster.jpg',
      );
      expect(
        svc.galleryPosterPath('gallery/u/123.mov'),
        'gallery/u/123_poster.jpg',
      );
    });

    test('path video galeri berada di folder gallery/ + berakhiran mp4', () {
      final p = svc.galleryVideoPath('u-1');
      expect(p, startsWith('gallery/u-1/'));
      expect(p, endsWith('.mp4'));
      expect(svc.isGalleryVideoPath(p), isTrue);
    });

    test('batas video galeri: 30 dtk / 8 MB (keputusan produk)', () {
      expect(StoragePhotoService.galleryVideoMaxMs, 30000);
      expect(StoragePhotoService.galleryVideoMaxBytes, 8 * 1024 * 1024);
    });
  });

  group('FaceCheck.checkVideo — wajah di video (female)', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('gv_frames_');
    });
    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    Future<File> frame(int i) async {
      final f = File('${dir.path}/f$i.jpg');
      await f.writeAsBytes([1, 2, 3]);
      return f;
    }

    test('mayoritas frame (3/4) memuat tepat 1 wajah → ok', () async {
      var i = 0;
      final r = await FaceCheck.checkVideo(
        'v.mp4',
        durationMs: 10000,
        frameAt: (_, _) => frame(i++),
        countFaces: (p) async => p.endsWith('f3.jpg') ? 0 : 1,
      );
      expect(r, FaceCheckResult.ok);
    });

    test('pas separuh (2/4) → ok (ambang mayoritas ≥50%)', () async {
      var i = 0;
      final r = await FaceCheck.checkVideo(
        'v.mp4',
        durationMs: 10000,
        frameAt: (_, _) => frame(i++),
        countFaces: (p) async => p.endsWith('f0.jpg') || p.endsWith('f1.jpg')
            ? 1
            : 0,
      );
      expect(r, FaceCheckResult.ok);
    });

    test('hanya 1/4 frame berwajah → noFace (tolak)', () async {
      var i = 0;
      final r = await FaceCheck.checkVideo(
        'v.mp4',
        durationMs: 10000,
        frameAt: (_, _) => frame(i++),
        countFaces: (p) async => p.endsWith('f0.jpg') ? 1 : 0,
      );
      expect(r, FaceCheckResult.noFace);
    });

    test('semua frame gagal diekstrak → failed (jangan blokir user)', () async {
      final r = await FaceCheck.checkVideo(
        'v.mp4',
        durationMs: 5000,
        frameAt: (_, _) async => null,
        countFaces: (_) async => 1,
      );
      expect(r, FaceCheckResult.failed);
    });

    test('detektor error di semua frame → failed (jangan blokir user)',
        () async {
      final r = await FaceCheck.checkVideo(
        'v.mp4',
        durationMs: 5000,
        frameAt: (_, _) => frame(0),
        countFaces: (_) async => -1,
      );
      expect(r, FaceCheckResult.failed);
    });

    test('frame sementara dibersihkan setelah cek', () async {
      final files = <File>[];
      await FaceCheck.checkVideo(
        'v.mp4',
        durationMs: 5000,
        frameAt: (_, _) async {
          final f = await frame(files.length);
          files.add(f);
          return f;
        },
        countFaces: (_) async => 1,
      );
      expect(files, hasLength(4));
      for (final f in files) {
        expect(await f.exists(), isFalse, reason: '${f.path} harus dihapus');
      }
    });
  });

  group('UserPhoto — isVideo & poster', () {
    test('default: bukan video, poster kosong', () {
      final p = UserPhoto.fromMap('1', {
        'userId': 'u',
        'photo': 'data',
        'createdAt': '2026-11-08T00:00:00Z',
      });
      expect(p.isVideo, isFalse);
      expect(p.poster, isEmpty);
    });

    test('fromMap membaca isVideo & poster', () {
      final p = UserPhoto.fromMap('2', {
        'userId': 'u',
        'photo': 'gallery/u/1.mp4',
        'createdAt': '2026-11-08T00:00:00Z',
        'isVideo': true,
        'poster': 'AAAA',
      });
      expect(p.isVideo, isTrue);
      expect(p.poster, 'AAAA');
    });
  });

  group('AuthService.uploadVideo', () {
    late FakeSupabaseHandler h;
    late SupabaseClient client;

    setUp(() {
      h = authedHandler('me-1');
      client = fakeSupabaseClient(handler: h);
      // AuthService memakai singleton StoragePhotoService — arahkan ke client
      // palsu yang sama supaya upload/download tidak menyentuh jaringan.
      StoragePhotoService.overrideInstance(
        StoragePhotoService.forTest(client),
      );
    });

    tearDown(StoragePhotoService.restoreInstance);

    test('female tanpa verifikasi wajah → ditolak, tanpa insert', () async {
      h.on('profiles', (_) => {'gender': 'female'});
      final auth = AuthService.forTest(client);
      await auth.signInAnonymously();

      await expectLater(
        auth.uploadVideo(
          videoBytes: Uint8List.fromList([1, 2, 3]),
          posterBytes: Uint8List.fromList([4]),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'pesan',
            contains('face_verification_required'),
          ),
        ),
      );
      final inserts = h.captured.where(
        (r) => r.method == 'POST' && r.url.path.contains('/user_photos'),
      );
      expect(inserts, isEmpty);
    });

    test('sukses: video + poster ke storage, row berisi path .mp4 + preview',
        () async {
      h.on(
        'storage',
        (req) => http.Response(
          // uploadBinary membaca key 'Key' dari respons.
          '{"Key":"ok"}',
          200,
          request: req,
          headers: {'content-type': 'application/json'},
        ),
      );
      final auth = AuthService.forTest(client);
      await auth.signInAnonymously();

      await auth.uploadVideo(
        videoBytes: Uint8List.fromList([1, 2, 3]),
        posterBytes: Uint8List.fromList([4, 5]),
        preview: 'blur',
        faceVerified: true,
      );

      final storagePosts = h.captured.where(
        (r) =>
            r.method == 'POST' &&
            r.url.path.contains('/storage/v1/object/'),
      );
      expect(storagePosts.length, 2, reason: 'video + poster');
      expect(
        storagePosts.any((r) => r.url.path.endsWith('.mp4')),
        isTrue,
      );
      expect(
        storagePosts.any((r) => r.url.path.endsWith('_poster.jpg')),
        isTrue,
      );
      final insert = h.captured.lastWhere(
        (r) => r.method == 'POST' && r.url.path.contains('/user_photos'),
      );
      final body = jsonDecode(insert.body) as Map<String, dynamic>;
      expect('${body['photo']}', endsWith('.mp4'));
      expect(body['photo_preview'], 'blur');
      expect(body['face_verified_at'], isNotNull);
    });

    test('video > 8 MB ditolak SEBELUM upload', () async {
      h.on('profiles', (_) => {'gender': 'male'});
      final auth = AuthService.forTest(client);
      await auth.signInAnonymously();

      await expectLater(
        auth.uploadVideo(
          videoBytes: Uint8List(StoragePhotoService.galleryVideoMaxBytes + 1),
          posterBytes: Uint8List.fromList([4]),
        ),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'pesan',
            contains('too large'),
          ),
        ),
      );
      expect(
        h.captured.where(
          (r) => r.method == 'POST' && r.url.path.contains('/storage/'),
        ),
        isEmpty,
      );
    });
  });

  group('getPhotos — video tidak diunduh jadi base64', () {
    late FakeSupabaseHandler h;
    late SupabaseClient client;

    setUp(() {
      h = authedHandler('me-1');
      client = fakeSupabaseClient(handler: h);
      StoragePhotoService.overrideInstance(
        StoragePhotoService.forTest(client),
      );
    });

    tearDown(StoragePhotoService.restoreInstance);

    test('video sendiri: path dipertahankan, hanya poster yang diunduh',
        () async {
      h.on('my_photos', (_) => [
            {
              'id': 1,
              'photo': 'gallery/me-1/vid1.mp4',
              'preview': 'blur',
              'created_at': '2026-01-01T00:00:00Z',
              'is_video': true,
            },
          ]);
      h.on(
        'storage',
        (req) => http.Response.bytes([9, 9, 9], 200, request: req),
      );
      final auth = AuthService.forTest(client);
      await auth.signInAnonymously();

      final photos = await auth.getPhotos('me-1');

      expect(photos, hasLength(1));
      final p = photos.first;
      expect(p.isVideo, isTrue);
      // Path mp4 TETAP path (bukan base64 hasil unduhan).
      expect(p.photo, 'gallery/me-1/vid1.mp4');
      expect(p.poster, base64Encode([9, 9, 9]));
      final downloads = h.captured.where(
        (r) =>
            r.method == 'GET' &&
            r.url.path.contains('/storage/v1/object/'),
      );
      expect(downloads, hasLength(1), reason: 'hanya poster, bukan video');
      expect(downloads.first.url.path, contains('_poster.jpg'));
      expect(called(h, 'my_photos'), isTrue);
    });

    test('video terkunci (profil orang lain): preview blur + isVideo tetap',
        () async {
      h.on('get_user_photos_access', (_) => [
            {
              'id': 9,
              'unlocked': false,
              'photo': 'blur-preview',
              'preview': 'blur-preview',
              'created_at': '2026-01-01T00:00:00Z',
              'is_video': true,
            },
          ]);
      final auth = AuthService.forTest(client);
      await auth.signInAnonymously();

      final photos = await auth.getPhotosWithAccess('other-2');

      expect(photos, hasLength(1));
      final p = photos.first;
      expect(p.isVideo, isTrue, reason: 'badge video untuk item terkunci');
      expect(p.unlocked, isFalse);
      expect(p.photo, 'blur-preview');
      expect(p.poster, isEmpty);
      expect(
        h.captured.where(
          (r) => r.url.path.contains('/storage/v1/object/'),
        ),
        isEmpty,
        reason: 'item terkunci tidak boleh mengunduh apa pun',
      );
    });

    test('foto biasa tetap diunduh jadi base64 (regresi)', () async {
      h.on('my_photos', (_) => [
            {
              'id': 2,
              'photo': 'gallery/me-1/pic1.jpg',
              'preview': 'blur',
              'created_at': '2026-01-01T00:00:00Z',
            },
          ]);
      h.on(
        'storage',
        (req) => http.Response.bytes([7, 7], 200, request: req),
      );
      final auth = AuthService.forTest(client);
      await auth.signInAnonymously();

      final photos = await auth.getPhotos('me-1');

      final p = photos.first;
      expect(p.isVideo, isFalse);
      expect(p.photo, base64Encode([7, 7]));
      expect(p.poster, isEmpty);
    });
  });
}
