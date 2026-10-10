import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/core/media/chat_photo_helper.dart';
import 'package:chatyuk/widgets/message/image_decode_core.dart';
import 'package:chatyuk/widgets/message/message_image.dart';

/// Mengunci anti-kedip bubble foto private chat: placeholder langsung
/// dicadangkan sesuai aspek (bukan kotak 200×200 dulu), dan hasil decode
/// dipakai ulang untuk path yang isinya sama (pending → versi server).
void main() {
  Uint8List jpegBytes(int w, int h) {
    final im = img.Image(width: w, height: h);
    return Uint8List.fromList(img.encodeJpg(im, quality: 75));
  }

  Uint8List pngBytes(int w, int h) {
    final im = img.Image(width: w, height: h);
    return Uint8List.fromList(img.encodePng(im));
  }

  group('parseImageDimensions', () {
    test('JPEG landscape terbaca', () {
      final dims = parseImageDimensions(jpegBytes(800, 400));
      expect(dims, isNotNull);
      expect(dims!.width, 800);
      expect(dims.height, 400);
    });

    test('JPEG portrait terbaca', () {
      final dims = parseImageDimensions(jpegBytes(400, 800));
      expect(dims, isNotNull);
      expect(dims!.width, 400);
      expect(dims.height, 800);
    });

    test('PNG terbaca', () {
      final dims = parseImageDimensions(pngBytes(640, 480));
      expect(dims, isNotNull);
      expect(dims!.width, 640);
      expect(dims.height, 480);
    });

    test('bytes korup → null (tidak crash)', () {
      expect(parseImageDimensions(Uint8List.fromList([0, 1, 2, 3])), isNull);
      expect(parseImageDimensions(Uint8List(0)), isNull);
      expect(
        parseImageDimensions(Uint8List.fromList([0xFF, 0xD8, 0xFF])),
        isNull,
      );
    });
  });

  group('photoViewSize', () {
    test('landscape 800×400 → 200×100', () {
      final s = photoViewSize(800, 400);
      expect(s.width, 200.0);
      expect(s.height, 100.0);
    });

    test('portrait tinggi dibatasi 280', () {
      final s = photoViewSize(400, 800);
      expect(s.height, 280.0);
      expect(s.width, closeTo(140.0, 0.01));
    });

    test('dimensi invalid → fallback 200×200', () {
      final s = photoViewSize(0, 0);
      expect(s.width, 200.0);
      expect(s.height, 200.0);
    });

    test('placeholder == gambar final untuk aspek sama', () {
      // Placeholder memakai rumus yang sama dengan gambar final → tidak ada
      // lompatan layout saat decode selesai.
      final dims = parseImageDimensions(jpegBytes(600, 300))!;
      final s = photoViewSize(dims.width, dims.height);
      expect(s.width, 200.0);
      expect(s.height, 100.0);
    });
  });

  group('warmPhotoCacheForPath', () {    test('path berisi sama langsung hit cache', () {
      final b64 = base64Encode(jpegBytes(320, 200));
      final decoded = DecodedImage(
        Uint8List.fromList([1, 2, 3]),
        320,
        200,
      );
      decodedImageCache[b64.hashCode] = decoded;
      try {
        const path = 'chat/warm-test/123.jpg';
        expect(decodedImageCache.containsKey(path.hashCode), isFalse);
        warmPhotoCacheForPath(path, b64);
        expect(decodedImageCache[path.hashCode], same(decoded));
      } finally {
        decodedImageCache.remove(b64.hashCode);
        decodedImageCache.remove('chat/warm-test/123.jpg'.hashCode);
      }
    });

    test('input kosong → no-op', () {
      warmPhotoCacheForPath('', 'abc');
      warmPhotoCacheForPath('chat/x/1.jpg', '');
    });
  });

  group('shouldPrefetchChatPhoto', () {
    final t0 = DateTime.utc(2026, 9, 28, 10, 0, 0);
    test('pesan baru dari lawan → true', () {
      expect(
        shouldPrefetchChatPhoto(
          lastSenderId: 'uid-lawan',
          myUid: 'uid-ku',
          lastMessageAt: t0,
          seenAt: null,
        ),
        isTrue,
      );
    });
    test('pesan sendiri → false (sudah ada lokal)', () {
      expect(
        shouldPrefetchChatPhoto(
          lastSenderId: 'uid-ku',
          myUid: 'uid-ku',
          lastMessageAt: t0,
          seenAt: null,
        ),
        isFalse,
      );
    });
    test('event non-pesan (waktu sama/lama) → false', () {
      expect(
        shouldPrefetchChatPhoto(
          lastSenderId: 'uid-lawan',
          myUid: 'uid-ku',
          lastMessageAt: t0,
          seenAt: t0,
        ),
        isFalse,
      );
      expect(
        shouldPrefetchChatPhoto(
          lastSenderId: 'uid-lawan',
          myUid: 'uid-ku',
          lastMessageAt: t0.subtract(const Duration(seconds: 1)),
          seenAt: t0,
        ),
        isFalse,
      );
    });
    test('pesan lebih baru dari penanda → true', () {
      expect(
        shouldPrefetchChatPhoto(
          lastSenderId: 'uid-lawan',
          myUid: 'uid-ku',
          lastMessageAt: t0.add(const Duration(seconds: 5)),
          seenAt: t0,
        ),
        isTrue,
      );
    });
  });

  // Sisi PENERIMA (dan pengirim): bubble foto landscape TIDAK boleh mulai
  // dari kotak 200×200 — frame pertama sudah 200×100 dan ukurannya tidak
  // berubah setelah decode selesai (tidak nge-blink).
  group('MessageImage placeholder penerima', () {
    Future<void> pumpPhoto(WidgetTester t, String b64, String id) {
      return t.pumpWidget(
        ProviderScope(child: MaterialApp(
          home:  Scaffold(
              body: MessageImage(
                imageData: b64,
                chatKey: 'private_a_b',
                messageId: id,
              ),
            ),
        )),
      );
    }

    testWidgets('landscape: frame pertama 200×100, final tetap', (t) async {
      final im = img.Image(width: 800, height: 400);
      final b64 = base64Encode(
        Uint8List.fromList(img.encodeJpg(im, quality: 75)),
      );
      await pumpPhoto(t, b64, 'recv-land-1');
      expect(t.getSize(find.byType(MessageImage)), const Size(200, 100));
      // Biarkan decode isolate selesai (waktu nyata), lalu beri frame untuk
      // setState + fade-in. Spinner placeholder animasi terus → jangan pakai
      // pumpAndSettle (tidak akan pernah settle).
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 800)),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(Image), findsOneWidget);
      expect(t.getSize(find.byType(MessageImage)), const Size(200, 100));
    });

    testWidgets('portrait: frame pertama ikut aspek, final tetap', (t) async {
      final im = img.Image(width: 400, height: 800);
      final b64 = base64Encode(
        Uint8List.fromList(img.encodeJpg(im, quality: 75)),
      );
      await pumpPhoto(t, b64, 'recv-port-1');
      final first = t.getSize(find.byType(MessageImage));
      expect(first.height, closeTo(280.0, 0.01));
      expect(first.width, closeTo(140.0, 0.01));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 800)),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byType(Image), findsOneWidget);
      expect(t.getSize(find.byType(MessageImage)), first);
    });
  });
}
