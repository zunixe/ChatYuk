import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../core/media/chat_background.dart';

/// Pemanasan PIPELINE GPU (Impeller/Vulkan) untuk efek layar chat.
///
/// Terukur di HP (2026-10-18): setelah APK baru dipasang, 2 kali pertama
/// buka private chat ada 1 frame raster ~26ms (tersendat) — Impeller membuat
/// pipeline untuk efek yang BARU pertama dipakai (opacity transisi,
/// ShaderMask lencana verifikasi, blur poster, bayangan bubble, wallpaper).
/// Percobaan ke-3 mulus (pipeline sudah ada) → "kadang lag, dicoba terus
/// jadi tidak".
///
/// Solusi: SEKALI per proses, ±2 detik setelah frame pertama (app tenang),
/// gambar efek-efek itu di area 2×2 px pojok kiri-atas (di balik status bar,
/// tak bisa disentuh) selama beberapa frame, lalu lepas. Digambar DI LAYAR
/// (bukan toImage offscreen) agar varian pipeline sama dengan yang dipakai
/// layar chat.
class GpuWarmup extends StatefulWidget {
  const GpuWarmup({super.key});

  /// Jumlah frame efek digambar (beberapa agar pipeline async tuntas).
  static const int frames = 8;

  @override
  State<GpuWarmup> createState() => _GpuWarmupState();
}

class _GpuWarmupState extends State<GpuWarmup> {
  static bool _done = false;
  bool _show = false;
  int _left = 0;
  Timer? _start;

  @override
  void initState() {
    super.initState();
    if (_done) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _start = Timer(const Duration(seconds: 2), () {
        if (!mounted || _done) return;
        _done = true;
        _left = GpuWarmup.frames;
        setState(() => _show = true);
        _tick();
      });
    });
  }

  void _tick() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _left--;
      if (_left <= 0) {
        setState(() => _show = false);
      } else {
        // Paksa frame berikutnya tetap menggambar efek.
        setState(() {});
        _tick();
      }
    });
  }

  @override
  void dispose() {
    _start?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final bg = chatBackgroundImage;
    return Positioned(
      left: 0,
      top: 0,
      width: 2,
      height: 2,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: RepaintBoundary(
            // Opacity < 1 di atas beberapa anak → saveLayer + alpha (sama
            // dengan FadeTransition halaman chat).
            child: Opacity(
              key: ValueKey(_left),
              opacity: 0.99,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (bg != null) RawImage(image: bg, fit: BoxFit.cover),
                  ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (b) => const LinearGradient(
                      colors: [Color(0xFFFFE082), Color(0xFFF59F00)],
                    ).createShader(b),
                    child: const ColoredBox(color: Colors.white),
                  ),
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 1, sigmaY: 1),
                    child: const ColoredBox(color: Color(0x10FFFFFF)),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(1),
                    child: const ColoredBox(color: Color(0x08000000)),
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x38000000),
                          blurRadius: 6,
                          offset: Offset(0, 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
