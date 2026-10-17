import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/core/media/chat_photo_helper.dart';
import 'package:chatyuk/core/cache/post_photo_cache.dart';
import 'package:chatyuk/widgets/post/post_photo_grid.dart';

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
}

void _noop(int _) {}
