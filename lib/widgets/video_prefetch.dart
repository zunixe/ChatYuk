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

  /// Maks poster dihangatkan per chat per sesi. 6 (dulu 2) — cukup untuk
  /// beberapa video terbaru; hanya POSTER yang disimpan (kecil), bukan video.
  static const int maxPerChat = 6;

  static final Set<String> _warmed = {};

  /// Downloader byte video (path → bytes). Di-inject dari StoragePhotoService.
  static Future<Uint8List?> Function(String path)? downloader;

  /// Generator poster dari FILE video lokal (path → JPEG bytes).
  /// Di-inject dari StoragePhotoService.storyVideoPoster.
  static Future<Uint8List?> Function(String videoFilePath)? posterGenerator;

  static String _posterKey(String videoPath) => posterKeyFor(videoPath);

  /// Kunci cache poster — SATU sumber untuk [VideoPrefetch] & [ChatVideoBubble].
  /// JANGAN bikin kunci serupa di tempat lain (kunci beda = selalu MISS =
  /// "card ngeload"). Format: `video_poster:<path>`.
  static String posterKeyFor(String videoPath) => 'video_poster:$videoPath';

  /// Hangatkan SATU video (path storage) → poster disk.
  ///
  /// [videoBytes] & [posterBytes] OPSIONAL: bila pengirim sudah punya bytes
  /// lokal (hasil kompres) + poster (hasil generate sebelum kirim), kirimkan
  /// lewat sini → TIDAK perlu unduh ulang video dari server (dulu `warmOne`
  /// selalu download → boros kuota & lambat). Bila null, fallback unduh
  /// (dipakai untuk video lawan).
  ///
  /// PENTING: yang disimpan ke [MediaDiskCache] HANYA POSTER (kecil, ~20-50KB),
  /// BUKAN video bytes (bisa puluhan MB — akan mengisi kuota 250MB bersama
  /// foto/avatar/voice & meng-evict LRU → poster/foto lain hilang → "cold
  /// start reload lagi"). Video bytes untuk playback ditangani mekanisme
  /// terpisah (`ChatVideoBubble._ensureLocalFile` → file temp native).
  static Future<void> warmOne(
    String videoPath, {
    Uint8List? videoBytes,
    Uint8List? posterBytes,
  }) async {
    if (videoPath.isEmpty) return;
    try {
      final hit = MediaDiskCache.instance.readSync(_posterKey(videoPath));
      final hasPoster = hit != null && hit.isNotEmpty;

      // Poster diberikan langsung (pengirim) → tulis, selesai (tanpa unduh).
      if (posterBytes != null && posterBytes.isNotEmpty) {
        if (!hasPoster) {
          await MediaDiskCache.instance.write(_posterKey(videoPath), posterBytes);
        }
        return;
      }
      if (hasPoster) return;

      // Bytes lokal ada tapi poster belum → generate LOKAL (tanpa unduh).
      if (videoBytes != null && videoBytes.isNotEmpty) {
        final gen = posterGenerator;
        if (gen == null) return;
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/vp1_${videoPath.hashCode.abs()}.mp4');
        await f.writeAsBytes(videoBytes, flush: true);
        final poster = await gen(f.path);
        if (poster != null && poster.isNotEmpty) {
          await MediaDiskCache.instance.write(_posterKey(videoPath), poster);
        }
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
        return;
      }

      // Tidak ada bytes lokal → unduh video, generate poster, BUANG video bytes
      // (jangan simpan ke cache kecil — cukup poster + file temp sementara).
      final dl = downloader;
      final gen = posterGenerator;
      if (dl == null || gen == null) return;
      final bytes = await dl(videoPath);
      if (bytes == null || bytes.isEmpty) return;
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
          // Tulis file temp HANYA untuk generate poster, lalu BUANG.
          // JANGAN simpan video bytes ke MediaDiskCache (kuota 250MB dipakai
          // bersama foto/avatar/voice → video besar akan meng-evict LRU =
          // "cold start reload lagi").
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
