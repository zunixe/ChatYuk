import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/cache/media_disk_cache.dart';
import '../models/message_model.dart';

/// Prefetch POSTER video chat lintas-instance (pola sama `VoicePrefetch`).
///
/// Kenapa: voice sudah anti-blink saat cold start karena `VoicePrefetch.warmChat`
/// mengunduh byte & menulis ke [MediaDiskCache] SEBELUM bubble tampil. Video
/// tidak punya padanannya → poster baru di-generate saat bubble muncul →
/// "ngeblink". Prefetch ini: unduh video terbaru (bounded) → generate poster
/// → simpan ke disk cache `video_poster:<path>` (kunci SAMA dgn
/// `ChatVideoBubble._posterKey`) sehingga `initState` bubble HIT-sync.
///
/// Boundary (AGENTS.md): widgets dilarang import services/ → downloader &
/// generator poster DIINJEKSI dari luar (di-wire di `main.dart`).
class VideoPrefetch {
  VideoPrefetch._();

  /// Maks poster dihangatkan per chat per sesi (video besar → batasi ketat).
  static const int maxPerChat = 2;

  static final Set<String> _warmed = {};

  /// Downloader byte video (path → bytes). Di-inject dari StoragePhotoService.
  static Future<Uint8List?> Function(String path)? downloader;

  /// Generator poster dari FILE video lokal (path → JPEG bytes).
  /// Di-inject dari StoragePhotoService.storyVideoPoster.
  static Future<Uint8List?> Function(String videoFilePath)? posterGenerator;

  static String _posterKey(String videoPath) => 'video_poster:$videoPath';

  /// Hangatkan SATU video (path storage) → poster disk. Dipakai setelah
  /// pengirim sukses upload (bubble versi server langsung anti-blink saat
  /// cold start berikutnya).
  static Future<void> warmOne(String videoPath) async {
    if (videoPath.isEmpty) return;
    final dl = downloader;
    final gen = posterGenerator;
    if (dl == null || gen == null) return;
    try {
      final hit = MediaDiskCache.instance.readSync(_posterKey(videoPath));
      if (hit != null && hit.isNotEmpty) return;
      final bytes = await dl(videoPath);
      if (bytes == null || bytes.isEmpty) return;
      unawaited(MediaDiskCache.instance.write(videoPath, bytes));
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/vp1_${videoPath.hashCode.abs()}.mp4');
      await f.writeAsBytes(bytes, flush: true);
      final poster = await gen(f.path);
      if (poster != null && poster.isNotEmpty) {
        await MediaDiskCache.instance.write(_posterKey(videoPath), poster);
      }
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    } catch (e) {
      if (kDebugMode) debugPrint('[VideoPrefetch] warmOne error: $e');
    }
  }

  static Future<void> warmChat(String chatKey, List<MessageModel> msgs) async {
    if (chatKey.isEmpty || msgs.isEmpty) return;
    if (_warmed.contains(chatKey)) return;
    if (_warmed.length > 50) _warmed.clear();
    _warmed.add(chatKey);
    final dl = downloader;
    final gen = posterGenerator;
    if (dl == null || gen == null) return;
    try {
      // Video dari lawan = path storage (bukan base64 pending). Ambil terbaru.
      final videos = msgs
          .where(
            (m) =>
                (m.type == 'video' ||
                    m.type == 'video_once' ||
                    m.type == 'video_once_expired') &&
                m.imageData.isNotEmpty &&
                !m.imageData.startsWith('data:') &&
                !m.imageData.contains('\n') && // bukan base64 panjang
                m.imageData.contains('/'), // path storage (bucket/…)
          )
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      for (final m in videos.take(maxPerChat)) {
        try {
          // Sudah ada poster di disk → lewati (hemat).
          final hit = MediaDiskCache.instance.readSync(_posterKey(m.imageData));
          if (hit != null && hit.isNotEmpty) continue;
          final bytes = await dl(m.imageData);
          if (bytes == null || bytes.isEmpty) continue;
          // Video juga disimpan (bukan cuma poster) → play instan nanti.
          unawaited(MediaDiskCache.instance.write(m.imageData, bytes));
          // Tulis file temp → generate poster.
          final dir = await getTemporaryDirectory();
          final f = File(
            '${dir.path}/vp_${m.imageData.hashCode.abs()}.mp4',
          );
          await f.writeAsBytes(bytes, flush: true);
          final poster = await gen(f.path);
          if (poster != null && poster.isNotEmpty) {
            await MediaDiskCache.instance.write(_posterKey(m.imageData), poster);
          }
          // Bersihkan file temp.
          try {
            if (await f.exists()) await f.delete();
          } catch (_) {}
        } catch (e) {
          if (kDebugMode) debugPrint('[VideoPrefetch] item error: $e');
        }
      }
    } catch (_) {}
  }
}
