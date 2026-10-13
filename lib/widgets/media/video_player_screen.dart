import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/perf/media_probe.dart';
import '../../config/theme.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../utils.dart';

/// Pemutar video fullscreen: kontrol dasar (play/pause) + loop dimatikan
/// agar user tahu videonya selesai. Dipakai bubble chat DAN preview composer.
class VideoPlayerScreen extends StatefulWidget {
  /// File lokal (mode lama/langsung). Null bila pakai [fileLoader].
  final File? file;
  /// Loader file yang MENYUSUL — viewer dibuka SEGERA, file di-resolve di
  /// latar (menghilangkan "tunggu unduh video cold sebelum viewer tampil").
  final Future<File?> Function()? fileLoader;
  /// Poster (JPEG) untuk ditampilkan selama file dimuat (bukan layar hitam).
  final Uint8List? posterBytes;
  final int durationMs;
  const VideoPlayerScreen({
    super.key,
    this.file,
    this.fileLoader,
    this.posterBytes,
    this.durationMs = 0,
  }) : assert(file != null || fileLoader != null,
            'butuh file atau fileLoader');

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _failed = false;
  Stopwatch? _initSw;

  @override
  void initState() {
    super.initState();
    MediaProbe.videoScreenOpened();
    _initSw = MediaProbe.start();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      // File menyusul bila pakai loader (viewer sudah tampil + poster).
      final f = widget.file ?? await widget.fileLoader!();
      if (f == null) {
        if (mounted) setState(() => _failed = true);
        return;
      }
      final ctrl = VideoPlayerController.file(f);
      _ctrl = ctrl;
      MediaProbe.videoCtrlOpened();
      await ctrl.initialize().timeout(const Duration(seconds: 20));
      await ctrl.setLooping(false);
      await ctrl.play();
      // init → play() benar-benar dipanggil.
      MediaProbe.stop('video.tap→play', _initSw);
      if (!mounted) return;
      setState(() => _ready = true);
      // play() → frame pertama siap tampil.
      MediaProbe.stop('video.tap→open', _initSw);
    } catch (e) {
      dlog('[VideoPlayer] init gagal: $e');
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    if (_ctrl != null) MediaProbe.videoCtrlClosed();
    _ctrl?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _ctrl;
    if (c == null) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // SafeArea: video portrait penuh TANPA ini memanjang sampai ke
      // belakang menu navigasi Android bawah (overlap). Lihat PhotoViewer.
      body: SafeArea(
        child: Center(
          child: _failed
            ? Text(
                s.videoCompressFail,
                style: AppText.body.copyWith(color: Colors.white70),
              )
            : !_ready
            ? (widget.posterBytes != null
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.memory(
                        widget.posterBytes!,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox.shrink(),
                      ),
                      const CircularProgressIndicator(color: Colors.white),
                    ],
                  )
                : const CircularProgressIndicator(color: Colors.white))
            : GestureDetector(
                onTap: _togglePlay,
                child: AspectRatio(
                  aspectRatio: _ctrl!.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_ctrl!),
                      if (!_ctrl!.value.isPlaying)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            size: 34,
                            color: Colors.white,
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
