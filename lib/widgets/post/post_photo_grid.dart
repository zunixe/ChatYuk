import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../config/theme.dart';

/// Faktor lebar foto tunggal (fraksi area konten).
const double kSingleWidthFactor = 1.0;

/// Rasio fallback (w/h) bila rasio foto belum diketahui.
const double kCarouselFallbackAspect = 4 / 5;

/// Lebar tiap foto di baris multi (fraksi area konten).
const double kCarouselItemWidthFactor = 0.48;

/// Jarak antar-foto di baris multi.
const double kCarouselGap = 6;

/// Cap tinggi baris multi (fraksi lebar konten).
const double kCarouselMaxHeightFactor = 1.4;

/// Radius sudut foto.
const double kPhotoRadius = 14;

/// Grid foto post (single / multi carousel) — murni tampilan; seluruh data
/// (thumbs, aspects) + callback buka viewer masuk sebagai parameter.
class PostPhotoGrid extends StatelessWidget {
  final List<Uint8List?> thumbs;
  final List<double?> aspects;
  final double radius;
  final void Function(int index) onOpenViewer;

  const PostPhotoGrid({
    super.key,
    required this.thumbs,
    required this.aspects,
    required this.onOpenViewer,
    this.radius = kPhotoRadius,
  });

  double? _aspectOf(int i) =>
      i >= 0 && i < aspects.length ? aspects[i] : null;

  static ({double width, double height}) _photoBoxFor(
    double aspect,
    double maxW,
  ) {
    final w = maxW * kSingleWidthFactor;
    return (width: w, height: w / aspect);
  }

  double _carouselAspect() {
    final a = _aspectOf(0);
    return (a != null && a > 0) ? a : kCarouselFallbackAspect;
  }

  ({double width, double height}) _carouselItemBox(double maxW) {
    final a = _carouselAspect();
    final w = maxW * kCarouselItemWidthFactor;
    final naturalH = w / a;
    final maxH = maxW * kCarouselMaxHeightFactor;
    if (naturalH > maxH) return (width: maxH * a, height: maxH);
    return (width: w, height: naturalH);
  }

  ({double width, double height}) _placeholderBox(
    double maxW, {
    required bool multi,
  }) {
    if (multi) return _carouselItemBox(maxW);
    final a = _aspectOf(0);
    if (a != null && a > 0) return _photoBoxFor(a, maxW);
    final w = maxW * kSingleWidthFactor;
    return (width: w, height: w / kCarouselFallbackAspect);
  }

  @override
  Widget build(BuildContext context) {
    final loaded = <(Uint8List, int)>[
      for (var i = 0; i < thumbs.length; i++)
        if (thumbs[i] != null) (thumbs[i]!, i),
    ];
    final pathsLen = thumbs.length;
    final isMulti = pathsLen > 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        if (loaded.isEmpty) {
          final box = _placeholderBox(maxW, multi: isMulti);
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              key: const ValueKey('photo_placeholder'),
              width: box.width,
              height: box.height,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(radius),
              ),
            ),
          );
        }
        Widget photo(int i) => GestureDetector(
          onTap: () => onOpenViewer(loaded[i].$2),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Image.memory(
              loaded[i].$1,
              fit: BoxFit.cover,
              cacheWidth: 1080,
              gaplessPlayback: true,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
        );
        if (loaded.length == 1) {
          final a = _aspectOf(loaded[0].$2);
          final box = a != null && a > 0
              ? _photoBoxFor(a, maxW)
              : (
                  width: maxW * kSingleWidthFactor,
                  height: maxW * kSingleWidthFactor / kCarouselFallbackAspect,
                );
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              key: const ValueKey('photo_single'),
              width: box.width,
              height: box.height,
              child: photo(0),
            ),
          );
        }
        final box = _carouselItemBox(maxW);
        return SizedBox(
          key: const ValueKey('photo_multi'),
          height: box.height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            scrollCacheExtent: ScrollCacheExtent.pixels(0),
            itemCount: loaded.length,
            separatorBuilder: (_, _) => const SizedBox(width: kCarouselGap),
            itemBuilder: (_, i) => SizedBox(
              width: box.width,
              height: box.height,
              child: photo(i),
            ),
          ),
        );
      },
    );
  }
}
