import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/cache/chat_poster_cache.dart';

/// Poster foto chat: grid warna 8×8 (RGBA mentah) DILUKIS langsung lalu
/// di-blur — TANPA decode gambar, jadi tampil di frame yang SAMA dengan
/// build (beda dengan `Image.memory` yang selalu async → kotak kosong dulu).
class PosterGrid extends StatelessWidget {
  final Uint8List rgba;
  const PosterGrid({super.key, required this.rgba});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 200.0;
        final h = c.maxHeight.isFinite ? c.maxHeight : 200.0;
        final sigma = (w < h ? w : h) / ChatPosterCache.gridSide * 0.9;
        return ClipRect(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: sigma,
              sigmaY: sigma,
              tileMode: TileMode.clamp,
            ),
            child: CustomPaint(
              size: Size(w, h),
              painter: _GridPainter(rgba),
            ),
          ),
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  final Uint8List rgba;
  _GridPainter(this.rgba);

  @override
  void paint(Canvas canvas, Size size) {
    const n = ChatPosterCache.gridSide;
    if (rgba.length < n * n * 4) return;
    final cw = size.width / n;
    final ch = size.height / n;
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final i = (y * n + x) * 4;
        paint.color = Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]);
        // +0.5 px tumpang-tindih → tanpa garis celah antar sel.
        canvas.drawRect(
          Rect.fromLTWH(x * cw, y * ch, cw + 0.5, ch + 0.5),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => !identical(old.rgba, rgba);
}
