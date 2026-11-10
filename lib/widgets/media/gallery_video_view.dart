import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/cache/video_file_cache.dart';
import '../../providers/riverpod/service_locator.dart';
import '../../providers/riverpod/storage_provider.dart';
import '../../utils.dart';
import 'video_player_screen.dart';

/// Tombol play bulat (badge) di atas poster video — dipakai grid galeri
/// profil, hero profil orang lain, dan viewer full-screen.
class VideoPlayBadge extends StatelessWidget {
  final double size;
  const VideoPlayBadge({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.play_arrow_rounded,
        size: size * 0.62,
        color: Colors.white,
      ),
    );
  }
}

/// Full-screen satu video galeri profil: poster + tombol play → buka
/// [VideoPlayerScreen]. File video diunduh SEKALI lalu disimpan di
/// [VideoFileCache] (persisten, kuota sendiri) — buka berikutnya instan.
///
/// Dipakai viewer foto profil sendiri ([ProfilePhotoViewerScreen]) dan
/// profil orang lain ([UserPhotoViewer]) supaya perilakunya identik.
class GalleryVideoView extends StatelessWidget {
  /// Path storage video (`gallery/<uid>/<stamp>.mp4`).
  final String videoPath;

  /// Poster jernih (base64 JPEG) — dari field `UserPhoto.poster`.
  final String posterBase64;

  const GalleryVideoView({
    super.key,
    required this.videoPath,
    required this.posterBase64,
  });

  /// File lokal siap putar: cache persisten dulu, unduh bila miss.
  /// [storage] ditangkap SEBELUM navigasi (context bisa unmount saat
  /// unduhan berjalan).
  Future<File?> _ensureLocalFile(StorageNotifier storage) async {
    final hit = await VideoFileCache.instance.fileFor(videoPath);
    if (hit != null) return hit;
    final bytes = await storage.downloadBytes(videoPath);
    if (bytes == null || bytes.isEmpty) return null;
    return VideoFileCache.instance.put(videoPath, bytes);
  }

  void _open(BuildContext context) {
    final storage = safeStorage(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          fileLoader: () => _ensureLocalFile(storage),
          posterBytes: _posterBytes(),
        ),
      ),
    );
  }

  Uint8List? _posterBytes() {
    if (posterBase64.isEmpty) return null;
    try {
      final b = base64Decode(posterBase64);
      return b.isEmpty ? null : b;
    } catch (e) {
      dlog('[GalleryVideo] poster decode error: $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final poster = _posterBytes();
    return GestureDetector(
      onTap: () => _open(context),
      child: Stack(
        alignment: Alignment.center,
        fit: StackFit.expand,
        children: [
          if (poster != null)
            Image.memory(
              poster,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              // Poster ±600px — cukup; video full tidak di-decode di sini.
              cacheWidth: 1080,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          const VideoPlayBadge(size: 64),
        ],
      ),
    );
  }
}
