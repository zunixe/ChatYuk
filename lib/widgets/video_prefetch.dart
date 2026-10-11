import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../core/cache/media_disk_cache.dart';
import '../core/cache/message_cache.dart';
import '../core/cache/video_file_cache.dart';
import '../models/message_model.dart';

/// Prefetch video chat lintas-instance: POSTER ke [MediaDiskCache] +
/// VIDEO ke [VideoFileCache] (persisten, seperti voice).
///
/// Kenapa: voice langsung tampil saat cold start karena bytes-nya tersimpan
/// persisten SEBELUM bubble tampil. Video dulu tidak punya padanannya → poster
/// baru di-generate + video diunduh saat bubble muncul → "ngeblink/ngeload".
/// Sekarang: unduh video terbaru (bounded) → simpan video ke VideoFileCache
/// (kuota 1GB sendiri + LRU) + generate poster → simpan ke MediaDiskCache.
/// Sekali dibuka/di-warm → cold start berikutnya langsung kebuka (persis voice).
///
/// Kunci poster `video_poster:<path>` SAMA dengan `ChatVideoBubble._posterKey`
/// sehingga `initState` bubble HIT-sync.
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

  /// Lebar decode poster (px) — SATU sumber. Dipakai [posterProvider] (bubble)
  /// DAN precache → kunci image-cache IDENTIK (kalau beda: precache sia-sia,
  /// decode ulang saat bubble mount = kedip).
  static const int posterDecodeWidth = 400;

  /// ImageProvider poster — SATU sumber agar kunci cache konsisten antara
  /// precache (saat tap) dan render bubble.
  ///
  /// PENTING: `MemoryImage` memakai `hashCode(Uint8List)` sebagai kunci
  /// equality image-cache. `MediaDiskCache.readSync` mengembalikan instance
  /// BARU tiap panggilan → kalau provider dibentuk dari bytes berbeda, kunci
  /// BEDA → precache sia-sia & decode ulang (kedip). Karena itu bytes poster
  /// di-cache DI MEMORI per path ([_posterBytesMem]) sehingga instance SAMA
  /// dipakai precache & bubble → kunci identik.
  static final Map<String, Uint8List> _posterBytesMem = {};

  /// Bytes poster stabil (instance sama) untuk [videoPath]; null bila belum ada
  /// di disk. Instance di-cache memori agar kunci image-cache konsisten.
  static Uint8List? posterBytesStable(String videoPath) {
    final cached = _posterBytesMem[videoPath];
    if (cached != null) return cached;
    final p = MediaDiskCache.instance.readSync(posterKeyFor(videoPath));
    if (p == null || p.isEmpty) return null;
    if (_posterBytesMem.length > 64) _posterBytesMem.clear();
    _posterBytesMem[videoPath] = p;
    return p;
  }

  /// BITMAP poster siap-pakai (sudah di-decode) per path. Render via [RawImage]
  /// = NOL decode di frame pertama → benar-benar langsung tampil seperti voice.
  /// Diisi saat tap (precachePosters) & saat bubble pertama generate.
  static final Map<String, ui.Image> _posterImages = {};

  /// Ambil bitmap poster siap-render (sinkron). null bila belum di-decode.
  static ui.Image? posterImageSync(String videoPath) => _posterImages[videoPath];

  /// Future decode poster yang sedang berjalan (kalau ada) — dipakai bubble
  /// untuk MENUNGGU sebentar agar frame pertama sudah poster (buka-1 tidak
  /// 'ngeload'). Key = videoPath.
  static final Map<String, Future<void>> _pendingDecode = {};

  static Future<void>? pendingDecode(String videoPath) =>
      _pendingDecode[videoPath];

  /// Decode poster → [ui.Image] (target lebar [posterDecodeWidth]) & simpan.
  /// Sinkron dari sisi pemanggil berikutnya (posterImageSync) = nol decode.
  static Future<void> decodePosterFor(String videoPath, Uint8List bytes) async {
    await _decodePosterImage(videoPath, bytes);
  }

  static Future<void> _decodePosterImage(String videoPath, Uint8List bytes) async {
    if (_posterImages.containsKey(videoPath)) return;
    final existing = _pendingDecode[videoPath];
    if (existing != null) {
      await existing;
      return;
    }
    final fut = _doDecodePoster(videoPath, bytes);
    _pendingDecode[videoPath] = fut;
    try {
      await fut;
    } finally {
      _pendingDecode.remove(videoPath);
    }
  }

  static Future<void> _doDecodePoster(String videoPath, Uint8List bytes) async {
    if (_posterImages.containsKey(videoPath)) return;
    try {
      // Coba muat BITMAP PERSISTEN dulu (raw RGBA dari sesi sebelumnya) →
      // decodeImageFromPixels ~0ms (nol decode JPEG) → cold start langsung.
      final persisted = await _loadPersistedBitmap(videoPath);
      if (persisted != null) {
        if (_posterImages.length > 64) _posterImages.clear();
        _posterImages[videoPath] = persisted;
        return;
      }
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: posterDecodeWidth,
      );
      final frame = await codec.getNextFrame();
      if (_posterImages.length > 64) _posterImages.clear();
      _posterImages[videoPath] = frame.image;
      // Simpan bitmap mentah ke disk → cold start berikutnya nol decode.
      unawaited(_persistBitmap(videoPath, frame.image));
    } catch (e) {
      if (kDebugMode) debugPrint('[VideoPrefetch] decode poster err: $e');
    }
  }

  /// Ukuran bitmap tersimpan per path (bytes) → file di direktori VideoFileCache
  /// (persisten). Format: [4 byte W][4 byte H][RGBA...] agar muat cepat.
  static String _bitmapKey(String videoPath) => 'poster_bmp_${videoPath.hashCode}';

  static Future<ui.Image?> _loadPersistedBitmap(String videoPath) async {
    try {
      final f = await _bmpFile(videoPath);
      if (!f.existsSync() || f.lengthSync() < 8) return null;
      final b = f.readAsBytesSync();
      final bd = ByteData.sublistView(b);
      final w = bd.getUint32(0);
      final h = bd.getUint32(4);
      if (w == 0 || h == 0 || b.length < 8 + w * h * 4) return null;
      final pixels = Uint8List.sublistView(b, 8);
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels, w, h, ui.PixelFormat.rgba8888, completer.complete,
      );
      // await di dalam try → bukan "return future tanpa await".
      final img = await completer.future;
      return img;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _persistBitmap(String videoPath, ui.Image img) async {
    try {
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) return;
      final w = img.width, h = img.height;
      final out = Uint8List(8 + w * h * 4);
      final od = ByteData.sublistView(out);
      od.setUint32(0, w);
      od.setUint32(4, h);
      out.setRange(8, out.length, bd.buffer.asUint8List());
      final f = await _bmpFile(videoPath);
      await f.writeAsBytes(out, flush: false);
    } catch (_) {}
  }

  static Future<File> _bmpFile(String videoPath) async {
    final dir = await VideoFileCache.instance.cacheDir();
    return File('${dir.path}/${mediaCacheFileName(_bitmapKey(videoPath))}.bmp');
  }

  /// Kosongkan cache bytes poster di memori (logout / uji).
  static void clearPosterMem() => _posterBytesMem.clear();

  /// Simpan bytes poster ke mem-cache stabil (instance SAMA) — dipanggil bubble
  /// setelah generate, supaya render/precache berikutnya memakai kunci
  /// image-cache identik (cegah decode ulang = kedip).
  static void rememberPoster(String videoPath, Uint8List bytes) {
    if (videoPath.isEmpty || bytes.isEmpty) return;
    if (_posterBytesMem.length > 64) _posterBytesMem.clear();
    _posterBytesMem[videoPath] = bytes;
    // Decode ke bitmap siap-render (fire-and-forget) → render berikutnya nol
    // decode (RawImage).
    unawaited(_decodePosterImage(videoPath, bytes));
  }

  static ImageProvider posterProvider(Uint8List posterBytes) =>
      ResizeImage(MemoryImage(posterBytes), width: posterDecodeWidth);

  /// Pre-decode poster video ke image cache SEBELUM layar chat tampil.
  /// Dipanggil paralel saat TAP kartu chat (di list/online) — decode berjalan
  /// selama transisi 150ms → frame pertama chat langsung poster (tanpa pop
  /// 1-2 frame decode pertama `Image.memory`). Inilah yang membuat voice
  /// "langsung kebuka": voice tak butuh decode; video butuh, jadi decode-nya
  /// dimajukan ke momen tap.
  ///
  /// Aman dipanggil kapan pun: no-op bila disk belum siap / poster belum ada
  /// / context sudah unmounted. Tidak melempar.
  static Future<void> precachePosters(
    BuildContext context,
    String chatKey,
  ) async {
    try {
      // Tunggu prewarm (maks 1 dtk) — tanpa ini readSync selalu null saat
      // cold start cepat → precache gagal → pop-in tetap terjadi.
      await MediaDiskCache.instance.waitReady();
      if (!context.mounted) return;
      final msgs =
          MessageCache.instance.peekMessages(chatKey) ?? const <MessageModel>[];
      var n = 0;
      for (final m in msgs) {
        if (n >= maxPerChat) break;
        if (!_isVideoPath(m)) continue;
        final p = posterBytesStable(m.imageData);
        if (p == null || p.isEmpty) continue;
        if (!context.mounted) return;
        // Decode ke bitmap siap-render (RawImage) — INI yang bikin poster
        // tampil NOL-decode saat bubble mount (seperti voice). "precacheImage"
        // lama tak cukup: bubble tetap decode via Image widget.
        await _decodePosterImage(m.imageData, p);
        n++;
      }
    } catch (_) {}
  }

  /// True bila pesan ini video path storage (bukan base64 pending).
  static bool _isVideoPath(MessageModel m) =>
      (m.type == 'video' ||
          m.type == 'video_once' ||
          m.type == 'video_once_expired') &&
      m.imageData.isNotEmpty &&
      !m.imageData.startsWith('data:') &&
      !m.imageData.contains('\n') &&
      m.imageData.contains('/');

  /// Tulis bytes ke file temp (untuk generate poster). Return file-nya.
  static Future<File?> _tempWrite(String name, Uint8List bytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes, flush: true);
      return f;
    } catch (_) {
      return null;
    }
  }

  /// Hangatkan SATU video: poster → [MediaDiskCache], video → [VideoFileCache]
  /// (persisten, seperti voice). Dipakai pengirim (bytes+poster lokal, tanpa
  /// unduh) maupun video lawan (fallback unduh).
  ///
  /// [videoBytes] & [posterBytes] OPSIONAL: bila pengirim sudah punya bytes
  /// lokal (hasil kompres) + poster (hasil generate sebelum kirim), kirimkan
  /// lewat sini → TIDAK perlu unduh ulang video dari server. Bila null,
  /// fallback unduh (dipakai untuk video lawan).
  ///
  /// PENTING: yang disimpan ke [MediaDiskCache] HANYA POSTER (kecil,
  /// ~20-50KB). Video bytes disimpan ke [VideoFileCache] (kuota 1GB sendiri
  /// + LRU) — BUKAN ke MediaDiskCache (kuota 250MB bersama foto/avatar/voice;
  /// video besar akan meng-evict LRU → poster/foto lain hilang → "cold start
  /// reload lagi").
  static Future<void> warmOne(
    String videoPath, {
    Uint8List? videoBytes,
    Uint8List? posterBytes,
  }) async {
    if (videoPath.isEmpty) return;
    try {
      final hit = MediaDiskCache.instance.readSync(_posterKey(videoPath));
      final hasPoster = hit != null && hit.isNotEmpty;

      // Poster diberikan langsung (pengirim) → tulis poster + persist video.
      if (posterBytes != null && posterBytes.isNotEmpty) {
        if (!hasPoster) {
          await MediaDiskCache.instance.write(_posterKey(videoPath), posterBytes);
        }
        if (videoBytes != null && videoBytes.isNotEmpty) {
          final vf = await VideoFileCache.instance.fileFor(videoPath);
          if (vf == null) {
            unawaited(VideoFileCache.instance.put(videoPath, videoBytes));
          }
        }
        return;
      }
      if (hasPoster) {
        // Poster ada — pastikan video juga persist (playback instan).
        if (videoBytes != null && videoBytes.isNotEmpty) {
          final vf = await VideoFileCache.instance.fileFor(videoPath);
          if (vf == null) {
            unawaited(VideoFileCache.instance.put(videoPath, videoBytes));
          }
        }
        return;
      }

      // Bytes lokal ada tapi poster belum → persist video + generate LOKAL.
      if (videoBytes != null && videoBytes.isNotEmpty) {
        final gen = posterGenerator;
        unawaited(VideoFileCache.instance.put(videoPath, videoBytes));
        if (gen == null) return;
        final f = await _tempWrite(
            'vp1_${videoPath.hashCode.abs()}.mp4', videoBytes);
        if (f == null) return;
        final poster = await gen(f.path);
        if (poster != null && poster.isNotEmpty) {
          await MediaDiskCache.instance.write(_posterKey(videoPath), poster);
        }
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
        return;
      }

      // Tidak ada bytes lokal → unduh video, persist, generate poster.
      final dl = downloader;
      final gen = posterGenerator;
      if (dl == null || gen == null) return;
      final bytes = await dl(videoPath);
      if (bytes == null || bytes.isEmpty) return;
      final vf = await VideoFileCache.instance.put(videoPath, bytes);
      final src =
          vf ?? await _tempWrite('vp1_${videoPath.hashCode.abs()}.mp4', bytes);
      if (src == null) return;
      final poster = await gen(src.path);
      if (poster != null && poster.isNotEmpty) {
        await MediaDiskCache.instance.write(_posterKey(videoPath), poster);
      }
      if (vf == null) {
        try {
          if (await src.exists()) await src.delete();
        } catch (_) {}
      }
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
          // PERSISTEN (seperti voice): simpan video ke VideoFileCache (kuota
          // 1GB sendiri + LRU) → sekali di-warm, cold start langsung kebuka.
          // BUKAN ke MediaDiskCache (kuota 250MB bersama foto/avatar/voice).
          final vf =
              await VideoFileCache.instance.put(m.imageData, bytes);
          // Tulis file temp HANYA untuk generate poster (pakai file persist
          // bila berhasil, supaya tak tulis ganda), lalu generate.
          final src = vf ??
              await _tempWrite(
                  'vp_${m.imageData.hashCode.abs()}.mp4', bytes);
          if (src == null) continue;
          final poster = await gen(src.path);
          if (poster != null && poster.isNotEmpty) {
            await MediaDiskCache.instance.write(_posterKey(m.imageData), poster);
          }
          // Bersihkan file temp (bukan file VideoFileCache).
          if (vf == null) {
            try {
              if (await src.exists()) await src.delete();
            } catch (_) {}
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[VideoPrefetch] item error: $e');
        }
      }
    } catch (_) {}
  }
}
