import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Renderer teks overlay story — DIPAKAI BERSAMA composer & viewer supaya
/// posisi/tampilan teks identik antara preview dan saat ditonton.
///
/// Posisi [x]/[y] dinormalisasi 0-1 terhadap kotak preview (AspectRatio
/// 9:16) — widget ini HARUS ditaruh di dalam kotak 9:16 yang sama.
class StoryTextOverlay extends StatelessWidget {
  final String text;
  final double x;
  final double y;
  final int colorIndex;
  final int sizeIndex;
  final double scale;
  final bool withBg;

  const StoryTextOverlay({
    super.key,
    required this.text,
    required this.x,
    required this.y,
    this.colorIndex = 0,
    this.sizeIndex = 1,
    this.scale = 1.0,
    this.withBg = false,
  });

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final color = colorIndex >= 0 && colorIndex < StoryText.palette.length
        ? StoryText.palette[colorIndex]
        : StoryText.palette.first;
    final style = TextStyle(
      fontSize: StoryText.size(sizeIndex) * scale.clamp(0.5, 3.0),
      fontWeight: FontWeight.w800,
      color: color,
      height: 1.2,
      shadows: [
        Shadow(
          color: Colors.black.withValues(alpha: 0.6),
          blurRadius: 6,
          offset: const Offset(1, 1),
        ),
      ],
    );
    return Align(
      alignment: Alignment(-1 + 2 * x.clamp(0.0, 1.0),
          -1 + 2 * y.clamp(0.0, 1.0)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: withBg
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  text,
                  style: style,
                  textAlign: TextAlign.center,
                ),
              )
            : Text(
                text,
                style: style,
                textAlign: TextAlign.center,
              ),
      ),
    );
  }
}
