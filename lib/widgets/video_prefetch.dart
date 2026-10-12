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
/// Job resize RGBA (dikirim ke isolate via [compute]).
class _ResizeJob {
  final Uint8List src;
  final int sw, sh, dw, dh;
  const _ResizeJob(this.src, this.sw, this.sh, this.dw, this.dh);
}

/// Resize RGBA [job.src] ([sw]×[sh]) ke [dw]×[dh] — nearest sampling.
/// Top-level (bukan method) agar bisa dipakai `compute`. Return Uint8List RGBA.
Uint8List? _nearestResizeRgba(_ResizeJob job) {
  try {
    final src = job.src;
    final out = Uint8List(job.dw * job.dh * 4);
    final xRatio = job.sw / job.dw;
    final yRatio = job.sh / job.dh;
    for (var y = 0; y < job.dh; y++) {
      final sy = (y * yRatio).floor().clamp(0, job.sh - 1);
      for (var x = 0; x < job.dw; x++) {
        final sx = (x * xRatio).floor().clamp(0, job.sw - 1);
        final si = (sy * job.sw + sx) * 4;
        final di = (y * job.dw + x) * 4;
        out[di] = src[si];
        out[di + 1] = src[si + 1];
        out[di + 2] = src[si + 2];
        out[di + 3] = src[si + 3];
      }
    }
    return out;
  } catch (_) {
    return null;
  }
}

/// Boundary (AGENTS.md): widgets dilarang import services/ → downloader &
/// generator poster DIINJEKSI dari luar (di-wire di `main.dart`).
class VideoPrefetch {  VideoPrefetch._();

  /// Maks poster dihangatkan per chat per sesi. 6 (dulu 2) — cukup untuk
  /// beberapa video terbaru; hanya POSTER yang disimpan (kecil), bukan video.
  static const int maxPerChat = 6;

  static final Set<String> _warmed = {};

  /// Downloader byte video (path → bytes). Di-inject dari StoragePhotoService.
  static Future<Uint8List?> Function(String path)? downloader;

  /// Generator poster dari FILE video lokal (path → JPEG bytes).
  /// Di-inject dari StoragePhotoService.storyVideoPoster.
  static Future<Uint8List?> Function(String videoFilePath)? posterGenerator;

  /// Downloader byte POSTER dari storage (path JPEG → bytes). Sama seperti
  /// [downloader] tapi diperuntukkan poster kecil dari pesan (`video_poster`).
  /// Di-inject dari StoragePhotoService.downloadBytes.
  static Future<Uint8List?> Function(String path)? posterDownloader;

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
    if (_posterBytesMem.length > _posterImageBudget) _posterBytesMem.clear();
    _posterBytesMem[videoPath] = p;
    return p;
  }

  /// BITMAP poster siap-pakai (sudah di-decode) per path. Render via [RawImage]
  /// = NOL decode di frame pertama → benar-benar langsung tampil seperti voice.
  /// Diisi saat tap (precachePosters) & saat bubble pertama generate.
  static final Map<String, ui.Image> _posterImages = {};

  /// Budget bitmap poster di memori (jumlah). ZERO-JANK/leak (2026-10-12):
  /// dulu 64 — poster video resolusi asli (1080p) = RGBA ~8 MB per bitmap →
  /// 64 × 8 MB = ~500 MB native heap (terukur via dumpsys meminfo:
  /// Native Heap 487 MB tak turun walau GC). Karena render hanya butuh
  /// lebar [posterDecodeWidth]=400, 12 cukup untuk viewport + scroll dekat.
  static const int _posterImageBudget = 12;

  /// Buang referensi bitmap poster dari cache.
  ///
  /// PENTING (bug 2026-10-12 "Cannot clone a disposed image"): JANGAN
  /// `dispose()` bitmap di sini. `_posterImages` adalah pool yang dipakai
  /// BERSAMA bubble aktif — `_clearPosterImages` dipanggil saat pool penuh
  /// (evict) atau decode baru, dan bubble yang MASIH dirender memegang
  /// referensi `_posterImg` ke bitmap lama. Dispose di sini → bubble render
  /// `RawImage` dgn handle mati → error "Cannot clone a disposed image" →
  /// kotak abu placeholder. Cukup LEPAS referensi; `ui.Image` di-GC setelah
  /// tak ada yang memegang (pool bounded 12 → retensi tetap terkendali).
  static void _clearPosterImages() {
    _posterImages.clear();
  }

  /// DISPOSE semua bitmap poster — HANYA saat logout/ganti akun (tak ada
  /// bubble aktif). Dipakai [clearPosterMem].
  static void _disposeAllPosterImages() {
    for (final img in _posterImages.values) {
      try {
        img.dispose();
      } catch (_) {}
    }
    _posterImages.clear();
  }

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
        if (_posterImages.length > _posterImageBudget) _clearPosterImages();
        _posterImages[videoPath] = persisted;
        return;
      }
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: posterDecodeWidth,
      );
      final frame = await codec.getNextFrame();
      // Dispose bitmap LAMA untuk kunci SAMA (kalau ada) — aman: tak ada
      // widget lain memegang objek yang baru saja digantikan dari pool untuk
      // path yang sama (pola sama decodedImageCache foto). Mencegah bitmap
      // menumpuk (regresi "Native Heap 515MB" 2026-10-12: pool di-clear tanpa
      // dispose + replace tanpa dispose → ui.Image native tak pernah bebas).
      final old = _posterImages.remove(videoPath);
      if (old != null && !identical(old, frame.image)) {
        try {
          old.dispose();
        } catch (_) {}
      }
      if (_posterImages.length > _posterImageBudget) _clearPosterImages();
      _posterImages[videoPath] = frame.image;
      // Simpan bitmap mentah ke disk → cold start berikutnya nol decode.
      unawaited(_persistBitmap(videoPath, frame.image));
    } catch (e) {
      if (kDebugMode) debugPrint('[VideoPrefetch] decode poster err: $e');
    }
  }

  /// Ukuran bitmap tersimpan per path (bytes) → file di direktori VideoFileCache
  /// (persisten). Format: [4 byte W][4 byte H][RGBA...] agar muat cepat.
  static String _bitmapKey(String videoPath) => 'poster_bmp_${hashKey64(videoPath)}';

  static Future<ui.Image?> _loadPersistedBitmap(String videoPath) async {
    try {
      final f = await _bmpFile(videoPath);
      if (!await f.exists() || await f.length() < 8) return null;
      // P1b: baca ASYNC (bukan readAsBytesSync) — bitmap poster RGBA bisa
      // 1-4MB; baca sinkron di UI thread = stall saat buka chat.
      final b = await f.readAsBytes();
      final bd = ByteData.sublistView(b);
      final w = bd.getUint32(0);
      final h = bd.getUint32(4);
      if (w == 0 || h == 0 || b.length < 8 + w * h * 4) return null;
      // Bitmap LAMA berukuran besar (sebelum downscale diperkenalkan) → abaikan
      // dan biarkan regenerate kecil. Mencegah native heap membengkak dari
      // file .bmp warisan (1080p RGBA ~8 MB).
      if (w > posterDecodeWidth * 2 || h > posterDecodeWidth * 4) return null;
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
      // ZERO-JANK/leak: downscale ke [posterDecodeWidth] DULU. Poster asli
      // (thumbnail video 1080p) = RGBA ~8 MB; file .bmp sebesar itu dibaca
      // ulang tiap cold start → native heap membengkak. Render hanya butuh
      // 400px, jadi simpan versi kecil.
      final small = await _downscaleImage(img, posterDecodeWidth);
      if (small == null) return;
      final bd = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
      small.dispose();
      if (bd == null) return;
      final w = small.width, h = small.height;
      final out = Uint8List(8 + w * h * 4);
      final od = ByteData.sublistView(out);
      od.setUint32(0, w);
      od.setUint32(4, h);
      out.setRange(8, out.length, bd.buffer.asUint8List());
      final f = await _bmpFile(videoPath);
      await f.writeAsBytes(out, flush: false);
    } catch (_) {}
  }

  /// Downscale [img] ke lebar [targetWidth] (aspek dipertahankan). Return null
  /// bila gagal / tidak perlu (sudah ≤ target). Dipakai agar bitmap tersimpan
  /// KECIL (hindari native heap ratusan MB dari poster 1080p).
  static Future<ui.Image?> _downscaleImage(ui.Image img, int targetWidth) async {
    if (img.width <= targetWidth) return null;
    try {
      final w = targetWidth;
      final h = (img.height * targetWidth / img.width).round();
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) return null;
      final small = await _resizeRgba(
        bd.buffer.asUint8List(),
        img.width,
        img.height,
        w,
        h,
      );
      return small;
    } catch (_) {
      return null;
    }
  }

  /// Resize RGBA [src] ([sw]×[sh]) ke [dw]×[dh] via nearest sampling di
  /// isolate (compute) lalu decodeImageFromPixels → ui.Image. Nearest cukup
  /// untuk thumbnail (cepat + murah); kualitas tak krusial untuk preview kecil.
  static Future<ui.Image?> _resizeRgba(
    Uint8List src,
    int sw,
    int sh,
    int dw,
    int dh,
  ) async {
    final out = await compute(_nearestResizeRgba, _ResizeJob(src, sw, sh, dw, dh));
    if (out == null) return null;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      out,
      dw,
      dh,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  static Future<File> _bmpFile(String videoPath) async {
    final dir = await VideoFileCache.instance.cacheDir();
    return File('${dir.path}/${mediaCacheFileName(_bitmapKey(videoPath))}.bmp');
  }

  /// Kosongkan cache bytes poster di memori (logout / uji). Di sini aman
  /// DISPOSE (layar chat sudah ditutup, tak ada bubble memegang bitmap).
  static void clearPosterMem() {
    _posterBytesMem.clear();
    _disposeAllPosterImages();
  }

  /// Simpan bytes poster ke mem-cache stabil (instance SAMA) — dipanggil bubble
  /// setelah generate, supaya render/precache berikutnya memakai kunci
  /// image-cache identik (cegah decode ulang = kedip).
  static void rememberPoster(String videoPath, Uint8List bytes) {
    if (videoPath.isEmpty || bytes.isEmpty) return;
    if (_posterBytesMem.length > _posterImageBudget) _posterBytesMem.clear();
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

      // Tidak ada bytes lokal → JANGAN unduh (ZERO-JANK 2026-10-11: video
      // penuh hanya saat tap play). Poster dibuat saat tap via
      // ChatVideoBubble._openFullscreen → _loadPoster(fromTap: true).
      // Dulu cabang ini mengunduh video penuh tiap buka chat / tiap video
      // baru masuk → kuota + bandwidth terkuras otomatis.
      return;
    } catch (e) {
      if (kDebugMode) debugPrint('[VideoPrefetch] warmOne error: $e');
    }
  }

  /// Hangatkan poster video chat dari CACHE LOKAL saja — TANPA download.
  ///
  /// ZERO-JANK (keputusan produk 2026-10-11): dulu tiap video terbaru tanpa
  /// poster diunduh PENUH (s.d. 6 video) saat chat dibuka → belasan MB
  /// otomatis + berebut bandwidth dengan foto. Sekarang video penuh HANYA
  /// diunduh saat user tap play (ChatVideoBubble._openFullscreen →
  /// _ensureLocalFile); poster dibuat saat itu dan persist untuk sesi
  /// berikutnya. Fungsi ini dipertahankan (API stabil) tapi tidak lagi
  /// menyentuh network — aman dipanggil di mana pun.
  static Future<void> warmChat(String chatKey, List<MessageModel> msgs) async {
    if (chatKey.isEmpty || msgs.isEmpty) return;
    if (_warmed.contains(chatKey)) return;
    if (_warmed.length > 50) _warmed.clear();
    _warmed.add(chatKey);
    // Sengaja tanpa kerja network: poster yang sudah ada di disk dibaca
    // sinkron oleh bubble sendiri (posterBytesStable); yang belum ada
    // dibuat saat tap. Tidak ada loop download di sini lagi.
  }
}
