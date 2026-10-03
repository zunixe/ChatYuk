import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/screens/post_composer_screen.dart';
import 'package:chatyuk/screens/online_users_screen.dart';
import 'package:chatyuk/screens/profile_screen.dart';

/// Test memori: kompres foto saat UPLOAD (avatar + post) & bukti bytes korup
/// tidak crash.
///
/// Latar: perubahan Oktober 2026 mengecilkan ukuran upload —
/// - Post  : 1200 q82 → **1080 q78** (file ~30% lebih kecil)
/// - Avatar: 1024 q90 → **640 q85**  (file ~50% lebih kecil)
/// Tujuan: storage lebih ringan, upload/download lebih cepat, disk cache
/// kecil, dan (tak langsung) spike memori berkurang. Test ini MENGUNCI
/// kontraknya supaya tidak balik membengkak.
///
/// Bonus: bytes korup harus aman (return null) — dulu `_processAvatarImage`
/// & `_processAvatar` TIDAK punya try/catch → crash RangeError (ditemukan
/// justru lewat test ini).
Uint8List _jpeg(int w, int h, [int r = 90, int g = 140, int b = 200]) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('processPostImageDim — foto post 1080px q78', () {
    test('lebar besar → di-resize ke 1080 (sisi acuan lebar)', () {
      final out = processPostImageDim(_jpeg(3000, 2000))!;
      expect(out.width, 1080);
      // 2000/3000 * 1080 = 720
      expect(out.height, 720);
      expect(img.decodeImage(out.bytes), isNotNull);
    });

    test('potret besar → lebar 1080, tinggi proporsional', () {
      final out = processPostImageDim(_jpeg(1200, 2400))!;
      expect(out.width, 1080);
      expect(out.height, 2160); // 2400/1200 * 1080
    });

    test('gambar kecil → DIPERBESAR ke lebar 1080 (semantik copyResize)', () {
      final out = processPostImageDim(_jpeg(400, 300))!;
      expect(out.width, 1080);
    });

    test('lebar hasil selalu tepat 1080 (kontrak ukuran)', () {
      for (final dim in [(2000, 1500), (4000, 3000), (800, 600)]) {
        final out = processPostImageDim(_jpeg(dim.$1, dim.$2))!;
        expect(out.width, 1080, reason: 'sumber ${dim.$1}x${dim.$2}');
      }
    });

    test('output JPEG valid & warna dipertahankan', () {
      final out = processPostImageDim(_jpeg(1080, 1080, 200, 30, 40))!;
      final p = img.decodeImage(out.bytes)!.getPixel(540, 540);
      expect(p.r, greaterThan(150), reason: 'anti corrupt/hitam');
    });

    test('bytes bukan gambar → null, tidak crash', () {
      expect(processPostImageDim([0, 1, 2, 3]), isNull);
      expect(processPostImageDim(<int>[]), isNull);
    });
  });

  group('processAvatarImage — avatar list online 640px q85', () {
    test('kotak (crop 1:1) → 640x640', () {
      final b64 = processAvatarImage(_jpeg(1024, 1024))!;
      final out = img.decodeImage(base64Decode(b64))!;
      expect(out.width, 640);
      expect(out.height, 640);
    });

    test('non-kotak → dipaksa 640x640 (crop area sudah 1:1 dari cropper)', () {
      final b64 = processAvatarImage(_jpeg(2000, 1200))!;
      final out = img.decodeImage(base64Decode(b64))!;
      expect(out.width, 640);
      expect(out.height, 640);
    });

    test('>640px → TURUN ke 640 (inti penghematan)', () {
      final b64 = processAvatarImage(_jpeg(1600, 1600))!;
      final out = img.decodeImage(base64Decode(b64))!;
      expect(out.width <= 640 && out.height <= 640, isTrue);
    });

    test('output JPEG valid & warna dipertahankan', () {
      final b64 = processAvatarImage(_jpeg(800, 800, 20, 180, 60))!;
      final p = img.decodeImage(base64Decode(b64))!.getPixel(320, 320);
      expect(p.g, greaterThan(120), reason: 'hijau harus dominan');
    });

    test('bytes korup → null, TIDAK crash (regresi: dulu crash)', () {
      expect(processAvatarImage(Uint8List.fromList([0, 1, 2, 3])), isNull);
      expect(processAvatarImage(Uint8List(0)), isNull);
      expect(processAvatarImage(Uint8List.fromList(List.filled(10, 7))), isNull);
    });
  });

  group('processAvatar — avatar profil 640px q85', () {
    test('kotak → 640x640', () async {
      final b64 = await processAvatar(_jpeg(1024, 1024));
      final out = img.decodeImage(base64Decode(b64!))!;
      expect(out.width, 640);
      expect(out.height, 640);
    });

    test('>640px → turun ke 640', () async {
      final b64 = await processAvatar(_jpeg(2000, 2000));
      final out = img.decodeImage(base64Decode(b64!))!;
      expect(out.width, 640);
    });

    test('bytes korup → null, TIDAK crash (regresi: dulu crash)', () async {
      expect(await processAvatar(Uint8List.fromList([0, 1, 2, 3])), isNull);
      expect(await processAvatar(Uint8List(0)), isNull);
    });

    test('konsisten dengan processAvatarImage (keduanya 640)', () async {
      final a = img.decodeImage(base64Decode((await processAvatar(_jpeg(1500, 1500)))!))!;
      final b = img.decodeImage(base64Decode(processAvatarImage(_jpeg(1500, 1500))!))!;
      expect(a.width, b.width);
      expect(a.height, b.height);
    });
  });
}
