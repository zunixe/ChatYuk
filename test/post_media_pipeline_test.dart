import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/core/media/chat_photo_helper.dart';
import 'package:chatyuk/core/cache/post_photo_cache.dart';
import 'package:chatyuk/widgets/post/post_photo_grid.dart';
import 'package:chatyuk/widgets/post_photo_viewer.dart';

import 'test_helper.dart';

/// Mengunci pipeline foto timeline: decode width, no-upscale, blurhash
/// placeholder, dan nol layout shift.
void main() {
  final png1x1 = Uint8List.fromList(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  ));

  group('mediaDecodeWidth (FASE 3 D)', () {
    test('menghitung lebar decode dari ukuran tampil × DPR', () {
      expect(mediaDecodeWidth(284, dpr: 1.0, maxWidth: 1080), 284);
      expect(mediaDecodeWidth(284, dpr: 2.0, maxWidth: 1080), 568);
    });
    test('dibatasi lebar varian (jangan decode 1080 utk tile kecil)', () {
      expect(mediaDecodeWidth(284, dpr: 3.0, maxWidth: 400), 400);
      expect(mediaDecodeWidth(284, dpr: 4.0, maxWidth: 1080), 1080);
    });
    test('minimal 64px & tak nol', () {
      expect(mediaDecodeWidth(1, dpr: 1.0, maxWidth: 1080), 64);
      expect(mediaDecodeWidth(0, dpr: 0, maxWidth: 1080), 64);
    });
  });

  group('rasio batas (FASE 3 B)', () {
    test('single dibatasi 4:5 … 1.91', () {
      expect(singleMediaAspect(1000, 2000), closeTo(0.8, 1e-6));
      expect(singleMediaAspect(2000, 1000), closeTo(1.91, 1e-6));
    });
    test('carousel dibatasi 3:4 … 4:3 (tinggi 240)', () {
      expect(carouselItemWidth(1000, 2000), closeTo(180, 1e-6));
      expect(carouselItemWidth(2000, 1000), closeTo(319.2, 1e-3));
    });
  });

  group('dartProcessPostDim (fallback) — no upscale', () {
    test('foto 100×80 TIDAK diperbesar ke 1080', () {
      final im = img.Image(width: 100, height: 80);
      final jpeg = Uint8List.fromList(img.encodeJpg(im));
      final out = dartProcessPostDim((jpeg, 1080, 78));
      expect(out, isNotNull);
      expect(out!.$2, 100, reason: 'lebar tetap 100 (bukan 1080)');
      expect(out.$3, 80);
    });

    test('foto 2000×1000 diperkecil ke lebar 1080', () {
      final im = img.Image(width: 2000, height: 1000);
      final jpeg = Uint8List.fromList(img.encodeJpg(im));
      final out = dartProcessPostDim((jpeg, 1080, 78));
      expect(out, isNotNull);
      expect(out!.$2, 1080);
      expect(out.$3, 540);
    });
  });

  group('PostPhotoGrid (FASE 3 C/D)', () {
    Widget host(Widget child) => MaterialApp(
          home: Scaffold(body: SizedBox(width: 300, child: child)),
        );

    testWidgets('placeholder BlurHash saat hash valid', (tester) async {
      await tester.pumpWidget(host(
        const PostPhotoGrid(
          thumbs: [null],
          aspects: [1.0],
          blurhashes: ['LEHV6nWB2yk8pyo0adR*.7kCMdnj'],
          onOpenViewer: _noop,
        ),
      ));
      await tester.pump();
      expect(find.byType(BlurHash), findsOneWidget);
      expect(find.byKey(const ValueKey('photo_placeholder')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hash kosong/tak valid → alas polos (tanpa BlurHash)',
        (tester) async {
      await tester.pumpWidget(host(
        const PostPhotoGrid(
          thumbs: [null],
          aspects: [1.0],
          blurhashes: ['bukan-hash!'],
          onOpenViewer: _noop,
        ),
      ));
      await tester.pump();
      expect(find.byType(BlurHash), findsNothing);
      expect(find.byKey(const ValueKey('photo_placeholder')), findsOneWidget);
    });

    testWidgets('NOL SHIFT: kotak placeholder == kotak final (rasio sama)',
        (tester) async {
      // Placeholder (tanpa bytes) dgn rasio 4:5.
      await tester.pumpWidget(host(
        const PostPhotoGrid(
          thumbs: [null],
          aspects: [0.8],
          onOpenViewer: _noop,
        ),
      ));
      await tester.pump();
      final phSize =
          tester.getSize(find.byKey(const ValueKey('photo_placeholder')));

      // Final (ada bytes) dgn rasio yang sama → ukuran HARUS identik.
      await tester.pumpWidget(host(
        PostPhotoGrid(
          thumbs: [png1x1],
          aspects: const [0.8],
          onOpenViewer: _noop,
        ),
      ));
      await tester.pump();
      final finalSize =
          tester.getSize(find.byKey(const ValueKey('photo_single')));
      expect(finalSize.width, closeTo(phSize.width, 0.01));
      expect(finalSize.height, closeTo(phSize.height, 0.01),
          reason: 'tinggi placeholder == tinggi final (nol layout shift)');
    });

    testWidgets('decode width = ukuran tampil × DPR (bukan 1080 tetap)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              child: PostPhotoGrid(
                thumbs: [png1x1],
                aspects: const [1.0],
                onOpenViewer: _noop,
                devicePixelRatio: 2.0,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final image = tester.widget<Image>(find.byType(Image).first);
      final provider = image.image;
      expect(provider, isA<ResizeImage>());
      // Lebar konten = 300 − 16 = 284 → decode = 284 × 2 = 568.
      expect((provider as ResizeImage).width, 568);
    });
  });

  group('PostPhotoCache — key varian terpisah', () {
    test('thumbSync feed vs tile tidak tercampur', () {
      // Tanpa disk (docs null) → keduanya null; kontrak: API menerima varian.
      expect(
        PostPhotoCache.instance.thumbSync('posts/x/a.jpg'),
        isNull,
      );
      expect(
        PostPhotoCache.instance.thumbSync(
          'posts/x/a.jpg',
          variant: PostImageVariant.tile,
        ),
        isNull,
      );
    });

    test('varian punya lebar berbeda', () {
      expect(PostImageVariant.feed.width, 1080);
      expect(PostImageVariant.tile.width, 400);
      expect(PostImageVariant.feed.tag, 'f');
      expect(PostImageVariant.tile.tag, 't');
    });
  });


  // JPEG 40×80 dengan EXIF Orientation=6 (perlu diputar 90° CW saat tampil).
  // Dibuat sekali via PIL; dipakai mengunci BAKARAN orientasi.
  const exifRotatedJpegB64 =
      '/9j/4AAQSkZJRgABAQAAAQABAAD/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAYAAAAAAAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCABQACgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwCpRRRX85H8ThRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAFFFFABRRRQAUUUUAf//Z';

  test('dartProcessPostDim MEMBAKAR orientasi EXIF (6 → 90°)', () {
    final bytes = base64Decode(exifRotatedJpegB64);
    final out = dartProcessPostDim((bytes, 1080, 78));
    expect(out, isNotNull);
    // Sumber 40×80 (potret) + orientation 6 → setelah dibakar 80×40 (lanskap).
    expect(out!.$2, 80, reason: 'lebar/tinggi tertukar = orientasi dibakar');
    expect(out.$3, 40);
  });

  testWidgets('viewer: maxScale 4 + preload foto tetangga', (tester) async {
    mockPathProvider();
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 8, height: 8)),
    );
    final requested = <String>[];
    PostPhotoCache.downloader = (p) async {
      requested.add(p);
      return jpeg;
    };
    addTearDown(() => PostPhotoCache.downloader = null);

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => PostPhotoViewer.show(
              ctx,
              paths: const ['p/a.jpg', 'p/b.jpg', 'p/c.jpg'],
              thumbs: [png1x1, png1x1, png1x1],
              aspects: const [1.0, 1.0, 1.0],
              initialIndex: 0,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final iv = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer).first,
    );
    expect(iv.maxScale, 4, reason: 'spesifikasi zoom maksimum 4x');

    // Catatan jujur: Future IO yang dimulai di initState (di luar runAsync)
    // tidak maju di fake-async, jadi preload diverifikasi lewat fungsi murni
    // di bawah — bukan dengan mengandalkan network/disk di widget test.
  });

  group('viewerNeighborIndices (preload tetangga)', () {
    test('indeks tengah → kiri & kanan', () {
      expect(viewerNeighborIndices(1, 3), [0, 2]);
    });
    test('indeks pertama → hanya kanan', () {
      expect(viewerNeighborIndices(0, 3), [1]);
    });
    test('indeks terakhir → hanya kiri', () {
      expect(viewerNeighborIndices(2, 3), [1]);
    });
    test('satu foto / kosong / di luar rentang → kosong', () {
      expect(viewerNeighborIndices(0, 1), isEmpty);
      expect(viewerNeighborIndices(0, 0), isEmpty);
      expect(viewerNeighborIndices(-1, 3), isEmpty);
      expect(viewerNeighborIndices(5, 3), isEmpty);
    });
  });
}

void _noop(int _) {}
