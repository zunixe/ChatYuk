import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../config/theme.dart';
import '../../core/cache/post_photo_cache.dart';

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

/// Grid media post ala Threads — murni tampilan; seluruh data (thumbs,
/// aspects) + callback buka viewer masuk sebagai parameter.
///
/// Aturan (rujukan desain Timeline):
///  - 1 media : lebar penuh kolom konten, tinggi = lebar ÷ rasio (rasio
///    dibatasi 4:5…1.91:1), BoxFit.cover (crop tengah).
///  - 2+ media: carousel horizontal (tinggi 240, lebar item = 240 × rasio,
///    rasio dibatasi 3:4…4:3, jarak 6), BUKAN grid. Carousel meluber sampai
///    tepi kanan layar (padding kanan 16 DI DALAM list) supaya item
///    berikutnya terlihat mengintip.
///  - Sudut radius 12, border tipis. Ketuk → viewer layar penuh.
///  - Saat gambar belum siap: kotak #1E1E1E dengan ukuran yang SAMA
///    (jangan sampai layout loncat).
class PostPhotoGrid extends StatelessWidget {
  final List<Uint8List?> thumbs;
  final List<double?> aspects;
  final double radius;
  /// Path storage sejajar `thumbs` — untuk kunci `ImageProvider` stabil
  /// (ImageCache hit → nol decode ulang saat scroll). Opsional.
  final List<String> paths;
  final void Function(int index) onOpenViewer;

  /// Jarak kanan DI LUAR media (dipakai media tunggal = 16; carousel = 0
  /// supaya bisa meluber sampai tepi layar).
  final double rightInset;

  const PostPhotoGrid({
    super.key,
    required this.thumbs,
    required this.aspects,
    required this.onOpenViewer,
    this.paths = const [],
    this.radius = kPhotoRadius,
    this.rightInset = 16,
  });

  double? _aspectOf(int i) =>
      i >= 0 && i < aspects.length ? aspects[i] : null;

  /// Lebar konten = lebar tersedia − gutter kanan.
  double _contentW(double maxW) => math.max(0, maxW - rightInset);

  /// Kotak media tunggal (lebar penuh kolom konten, tinggi dari rasio).
  ({double width, double height}) _singleBox(double maxW) {
    final w = _contentW(maxW);
    final a = _aspectOf(0);
    final aspect = (a != null && a > 0)
        ? a.clamp(kSingleMediaMinAspect, kSingleMediaMaxAspect)
        : 1.0;
    return (width: w, height: w / aspect);
  }

  Widget _media(
    BuildContext context, {
    required Uint8List bytes,
    required int srcIndex,
    required double width,
    required double height,
  }) {
    final path = srcIndex < paths.length ? paths[srcIndex] : '';
    // Provider STABIL per-path → ImageCache HIT walau bytes di-reload saat
    // kartu remount (anti "load ulang saat scroll").
    final provider = path.isNotEmpty
        ? PostPhotoCache.instance.imageProviderFor(path, bytes)
        : ResizeImage(MemoryImage(bytes), width: 1080);
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
    // Batasi jumlah media yang dirender (desain: maks 10).
    final count = math.min(thumbs.length, kMaxMediaPerPost);
    final loaded = <(Uint8List, int)>[
      for (var i = 0; i < count; i++)
        if (thumbs[i] != null) (thumbs[i]!, i),
    ];
    final total = count;
    final isMulti = total > 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;

        if (loaded.isEmpty) {
          final a0 = _aspectOf(0);
          final box = isMulti
              ? (
                  width: carouselItemWidth(a0 ?? 1, 1),
                  height: kCarouselItemHeight,
                )
              : _singleBox(maxW);
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              key: const ValueKey('photo_placeholder'),
              width: box.width,
              height: box.height,
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: AppTheme.divider, width: 0.5),
              ),
            ),
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
              ),
            ),
          );
        }

        // ── CAROUSEL (2+ media) ──
        // ListView meluber sampai tepi kanan layar (rightInset=0 saat dipanggil
        // dari PostCard) + padding kanan 16 DI DALAM list → item berikutnya
        // mengintip. Snapping per item (PageScrollPhysics).
        return SizedBox(
          key: const ValueKey('photo_multi'),
          height: kCarouselItemHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const PageScrollPhysics(),
            padding: const EdgeInsets.only(right: 16),
            scrollCacheExtent: ScrollCacheExtent.pixels(0),
            itemCount: loaded.length,
            separatorBuilder: (_, _) => const SizedBox(width: kCarouselGap),
            itemBuilder: (_, i) {
              final a = _aspectOf(loaded[i].$2);
              final ratio = (a != null && a > 0) ? a : 1.0;
              final w = carouselItemWidth(ratio, 1, itemHeight: kCarouselItemHeight);
              return _media(
                context,
                bytes: loaded[i].$1,
                srcIndex: loaded[i].$2,
                width: w,
                height: kCarouselItemHeight,
              );
            },
          ),
        );
      },
    );
  }
}
