import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

import '../../config/theme.dart';
import '../../core/cache/post_photo_cache.dart';
import '../../core/media/blurhash.dart';

/// Radius sudut semua media (ala Threads).
const double kPhotoRadius = 12;

/// Batas rasio (lebar ÷ tinggi) untuk media TUNGGAL: 4:5 (paling tinggi) s/d
/// 1.91:1 (paling lebar). Di luar batas → di-crop tengah (BoxFit.cover).
const double kSingleMediaMinAspect = 0.8; // 4:5
const double kSingleMediaMaxAspect = 1.91;

/// Tinggi seragam item carousel (media 2+).
const double kCarouselItemHeight = 240;

/// Batas rasio item carousel: 3:4 s/d 4:3.
const double kCarouselMinAspect = 0.75;
const double kCarouselMaxAspect = 1.33;

/// Jarak antar item carousel.
const double kCarouselGap = 6;

/// Maksimum media yang ditampilkan per postingan.
const int kMaxMediaPerPost = 10;

/// Rasio FALLBACK media tunggal saat dimensi belum diketahui (post lama).
/// Dipakai KONSISTEN (tidak diubah setelah thumb tiba) supaya layout tidak
/// pernah bergeser. 4:5 = batas potret, mengisi kartu dengan rapi.
const double kMediaFallbackAspect = 0.8;

/// Lebar decode maksimum untuk media (jangan melebihi sumber feed).
const int kMediaMaxDecodeWidth = 1080;

/// Rasio (lebar ÷ tinggi) untuk postingan dengan 1 foto/video.
/// Dibatasi 4:5 (0.8) sampai 1.91:1.
double singleMediaAspect(num width, num height) {
  if (width <= 0 || height <= 0) return 1.0;
  return (width / height).clamp(kSingleMediaMinAspect, kSingleMediaMaxAspect)
      .toDouble();
}

/// Lebar item carousel (postingan 2+ media) untuk tinggi tertentu.
/// Rasio dibatasi 3:4 (0.75) sampai 4:3 (1.33).
double carouselItemWidth(
  num width,
  num height, {
  double itemHeight = kCarouselItemHeight,
}) {
  final ratio = (width <= 0 || height <= 0) ? 1.0 : width / height;
  return itemHeight * ratio.clamp(kCarouselMinAspect, kCarouselMaxAspect);
}

/// Lebar decode (piksel) untuk sebuah kotak berlebar logis [logicalWidth] pada
/// perangkat ber-DPR [dpr] — dibatasi [maxWidth] (jangan decode lebih besar
/// dari sumber/varian) dan minimal 64px. Menghindari decode 1080px untuk tile
/// kecil (§ hemat RAM/GPU, anti-evict → anti-kedip).
int mediaDecodeWidth(
  double logicalWidth, {
  required double dpr,
  required int maxWidth,
}) {
  final raw = logicalWidth * dpr;
  return raw.round().clamp(64, maxWidth);
}

/// Grid media post ala Threads — murni tampilan; seluruh data (thumbs,
/// aspects, blurhashes) + callback buka viewer masuk sebagai parameter.
///
///  - 1 media : lebar penuh kolom konten, rasio dibatasi 4:5…1.91:1, cover.
///  - 2+ media: carousel horizontal (tinggi 240, lebar item = 240 × rasio,
///    rasio 3:4…4:3, jarak 6), meluber ke tepi kanan + snapping, maks 10.
///  - Placeholder: BlurHash (bila ada) atau alas #1E1E1E — ukuran SAMA dengan
///    final (nol layout shift).
///  - Decode dibatasi sesuai ukuran tampil (DPR) & varian (feed/tile).
class PostPhotoGrid extends StatelessWidget {
  final List<Uint8List?> thumbs;
  final List<double?> aspects;

  /// BlurHash sejajar `thumbs` ('' = tidak ada → alas #1E1E1E).
  final List<String> blurhashes;
  final double radius;

  /// Path storage sejajar `thumbs` — untuk kunci `ImageProvider` stabil.
  final List<String> paths;
  final void Function(int index) onOpenViewer;

  /// Jarak kanan DI LUAR media (media tunggal = 16; carousel = 0 agar meluber).
  final double rightInset;

  /// Device pixel ratio (untuk menghitung lebar decode yang tepat).
  final double devicePixelRatio;

  const PostPhotoGrid({
    super.key,
    required this.thumbs,
    required this.aspects,
    required this.onOpenViewer,
    this.blurhashes = const [],
    this.paths = const [],
    this.radius = kPhotoRadius,
    this.rightInset = 16,
    this.devicePixelRatio = 1.0,
  });

  double? _aspectOf(int i) =>
      i >= 0 && i < aspects.length ? aspects[i] : null;

  String _blurOf(int i) {
    if (i < 0 || i >= blurhashes.length) return '';
    final h = blurhashes[i];
    return BlurHashCodec.validate(h) ? h : '';
  }

  double _contentW(double maxW) => math.max(0, maxW - rightInset);

  /// Kotak media tunggal (lebar penuh kolom konten, tinggi dari rasio).
  ({double width, double height}) _singleBox(double maxW) {
    final w = _contentW(maxW);
    final a = _aspectOf(0);
    final aspect = (a != null && a > 0)
        ? a.clamp(kSingleMediaMinAspect, kSingleMediaMaxAspect)
        : kMediaFallbackAspect;
    return (width: w, height: w / aspect);
  }

  /// Placeholder: BlurHash bila valid, else alas #1E1E1E. Ukuran = final.
  Widget _placeholder(String hash, double width, double height) {
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
    );
    if (hash.isEmpty) {
      return Container(
        key: const ValueKey('photo_placeholder'),
        child: box,
      );
    }
    return Container(
      key: const ValueKey('photo_placeholder'),
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.divider, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: BlurHash(
        hash: hash,
        color: AppTheme.bgCard,
        imageFit: BoxFit.cover,
        duration: const Duration(milliseconds: 120),
      ),
    );
  }

  Widget _media(
    BuildContext context, {
    required Uint8List bytes,
    required int srcIndex,
    required double width,
    required double height,
    required PostImageVariant variant,
  }) {
    final path = srcIndex < paths.length ? paths[srcIndex] : '';
    // Lebar decode = ukuran tampil × DPR, dibatasi lebar varian (jangan
    // decode 1080px untuk tile 200px → hemat RAM/GPU, kurangi evict → anti
    // kedip saat scroll balik).
    final decodeW = mediaDecodeWidth(
      width,
      dpr: devicePixelRatio,
      maxWidth: variant.width,
    );
    final provider = path.isNotEmpty
        ? PostPhotoCache.instance
            .imageProviderFor(path, bytes, decodeWidth: decodeW)
        : ResizeImage(MemoryImage(bytes), width: decodeW, allowUpscaling: false);
    return GestureDetector(
      onTap: () => onOpenViewer(srcIndex),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppTheme.divider, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image(
          image: provider,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = math.min(thumbs.length, kMaxMediaPerPost);
    final loaded = <(Uint8List, int)>[
      for (var i = 0; i < count; i++)
        if (thumbs[i] != null && thumbs[i]!.isNotEmpty) (thumbs[i]!, i),
    ];
    final total = count;
    final isMulti = total > 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;

        // ── Placeholder (belum ada byte siap) ──
        if (loaded.isEmpty) {
          if (isMulti) {
            // Lebar mengikuti rasio item pertama (nol shift saat byte tiba).
            final a0 = _aspectOf(0);
            final w = carouselItemWidth(
              (a0 != null && a0 > 0) ? a0 : 1.0,
              1,
              itemHeight: kCarouselItemHeight,
            );
            return Align(
              alignment: Alignment.centerLeft,
              child: _placeholder(_blurOf(0), w, kCarouselItemHeight),
            );
          }
          final box = _singleBox(maxW);
          return Align(
            alignment: Alignment.centerLeft,
            child: _placeholder(_blurOf(0), box.width, box.height),
          );
        }

        // ── MEDIA TUNGGAL ──
        if (loaded.length == 1) {
          final box = _singleBox(maxW);
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              key: const ValueKey('photo_single'),
              width: box.width,
              height: box.height,
              child: _media(
                context,
                bytes: loaded[0].$1,
                srcIndex: loaded[0].$2,
                width: box.width,
                height: box.height,
                variant: PostImageVariant.feed,
              ),
            ),
          );
        }

        // ── CAROUSEL (2+ media) ──
        return SizedBox(
          key: const ValueKey('photo_multi'),
          height: kCarouselItemHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const PageScrollPhysics(),
            padding: const EdgeInsets.only(right: 16),
            // Preload item berikutnya (bounded) — hemat stutter saat geser.
            scrollCacheExtent: ScrollCacheExtent.pixels(0),
            itemCount: loaded.length,
            separatorBuilder: (_, _) => const SizedBox(width: kCarouselGap),
            itemBuilder: (_, i) {
              final a = _aspectOf(loaded[i].$2);
              final ratio = (a != null && a > 0) ? a : 1.0;
              final w = carouselItemWidth(
                ratio,
                1,
                itemHeight: kCarouselItemHeight,
              );
              // Preload tetangga (dedupe di cache) — tile variant (kecil).
              if (i + 1 < loaded.length) {
                final nxt = loaded[i + 1].$2;
                if (nxt < paths.length) {
                  unawaited(
                    PostPhotoCache.instance.thumb(
                      paths[nxt],
                      variant: PostImageVariant.tile,
                    ),
                  );
                }
              }
              return _media(
                context,
                bytes: loaded[i].$1,
                srcIndex: loaded[i].$2,
                width: w,
                height: kCarouselItemHeight,
                variant: PostImageVariant.tile,
              );
            },
          ),
        );
      },
    );
  }
}
