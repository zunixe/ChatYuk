import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../utils.dart';
import 'package:path_provider/path_provider.dart';
import '../media/native_image.dart';

// Thumbnail JPEG (~1024px) dari bytes asli — kini di NATIVE
// (`NativeImage.downscaleBytes`, fallback Dart) supaya decode+encode tidak
// memakai heap Dart. 512px terlihat blur saat foto single di-upscale selebar
// layar (1080px fisik).
@visibleForTesting
Future<Uint8List?> genPostThumb(Uint8List bytes) =>
    NativeImage.downscaleBytes(bytes, targetWidth: 1024, quality: 82);

/// Apakah total byte LRU melebihi cap (harus buang yang tertua)? Murni &
/// top-level supaya kontrak cap bisa dikunci tanpa filesystem/plugin.
@visibleForTesting
bool lruShouldEvict(int bytes, int cap) => bytes > cap;

/// Cap memori thumbnail post (30MB) — diekspos untuk test.
@visibleForTesting
const int postPhotoMemMaxBytes = 30 * 1024 * 1024;

/// Cache foto post timeline di DISK + MEMORY.
///
/// - File thumbnail (~1024px) disimpan sebagai JPEG biasa (foto post bersifat
///   publik, tidak perlu enkripsi seperti foto chat privat).
/// - Scroll ulang feed = baca disk (instan), TIDAK download ulang dari
///   Storage. Hanya miss pertama yang download full-res sekali, lalu
///   thumbnail dibuat di isolate.
/// Fungsi download bytes dari Storage — di-inject dari luar (main.dart)
/// supaya `core/` tidak bergantung pada `services/` (aturan boundary).
typedef PostPhotoDownloader = Future<Uint8List?> Function(String path);

class PostPhotoCache {
  PostPhotoCache._();
  static final PostPhotoCache instance = PostPhotoCache._();

  /// Wired di main.dart: `PostPhotoCache.downloader = StoragePhotoService.instance.downloadBytes`.
  static PostPhotoDownloader? downloader;

  static const _folderName = 'post_photos_v2';

  // In-memory thumbnail (path → bytes JPEG). LRU sederhana, cap 30MB.
  final Map<String, Uint8List> _mem = {};
  static const _memMaxBytes = 30 * 1024 * 1024;
  int _memBytes = 0;

  // Job yang sedang berjalan per path — penelepon kedua MENUNGGU hasil yang
  // sama, bukan "dilewati lalu dianggap gagal". Dulu pakai Set<String> +
  // `return null` untuk path in-flight → saat dua kartu/rebuild meminta path
  // yang sama bersamaan, penelepon kedua dapat null → ditandai GAGAL
  // permanen → gambar tidak pernah muncul ("tidak semua gambar keload").
  final Map<String, Future<Uint8List?>> _jobs = {};

  void _memPut(String path, Uint8List bytes) {
    _mem.remove(path);
    _mem[path] = bytes;
    _memBytes += bytes.length;
    while (lruShouldEvict(_memBytes, _memMaxBytes) && _mem.isNotEmpty) {
      final oldest = _mem.keys.first;
      _memBytes -= _mem.remove(oldest)!.length;
    }
  }

  Uint8List? _memGet(String path) => _mem[path];

  /// Buang SEMUA thumbnail dari RAM saja (file disk tetap). Dipakai saat OS
  /// memberi sinyal memory-pressure: thumbnail timeline bisa menahan 30MB
  /// (gambar RGBA/JPEG) → melepasnya mencegah GC storm saat app lama dipakai.
  /// Gambar dibaca ulang dari disk (murah) saat kartu di-build lagi.
  void trimMemCache() {
    _mem.clear();
    _memBytes = 0;
  }

  Future<Directory> _folder() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/$_folderName');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  String? _docs;
  bool get isReady => _docs != null;

  /// Warm-up SEBELUM frame pertama — simpan documents path supaya [thumbSync]
  /// (sinkron) bisa dipakai. Dipanggil di `main.dart` (composition root).
  Future<void> prewarm() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      _docs = dir.path;
      final folder = Directory('${_docs}/$_folderName');
      if (!folder.existsSync()) folder.createSync(recursive: true);
    } catch (e) {
      dlog('[PostPhotoCache] prewarm error: $e');
    }
  }

  /// Thumb SINKRON (RAM → disk) — dipakai `PostCard` di initState supaya frame
  /// pertama Timeline sudah foto (nol kedip), bukan placeholder lalu thumb
  /// menyusul. null bila belum ada (fallback jalur async `thumb()`).
  Uint8List? thumbSync(String path) {
    if (path.isEmpty) return null;
    final mem = _memGet(path);
    if (mem != null) return mem;
    final docs = _docs;
    if (docs == null) return null;
    try {
      final f = File('$docs/$_folderName/${path.hashCode}.jpg');
      if (!f.existsSync()) return null;
      final bytes = f.readAsBytesSync();
      if (bytes.isEmpty) return null;
      _memPut(path, bytes);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  File _fileFor(Directory folder, String path) =>
      File('${folder.path}/${path.hashCode}.jpg');

  // Full-res disimpan terpisah (suffix .full) supaya thumbnail & full bisa
  // punya umur berbeda dan tidak saling menimpa.
  File _fullFileFor(Directory folder, String path) =>
      File('${folder.path}/${path.hashCode}.full.jpg');

  /// Ambil thumbnail foto post. [path] adalah path storage (mis. `posts/uid/ts.jpg`).
  /// Penelepon paralel untuk path sama menunggu job yang sama (bukan gagal).
  Future<Uint8List?> thumb(String path) {
    if (path.isEmpty) return Future.value(null);
    final mem = _memGet(path);
    if (mem != null) return Future.value(mem);
    final existing = _jobs[path];
    if (existing != null) return existing;
    final job = _fetchThumb(path);
    _jobs[path] = job;
    return job.whenComplete(() {
      // Hapus HANYA job ini (job pengganti tak boleh ikut terhapus).
      if (identical(_jobs[path], job)) _jobs.remove(path);
    });
  }

  Future<Uint8List?> _fetchThumb(String path) async {
    try {
      final folder = await _folder();
      final f = _fileFor(folder, path);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        _memPut(path, bytes);
        return bytes;
      }
      final full = await (downloader?.call(path) ?? Future<Uint8List?>.value());
      if (full == null) return null;
      // Decode+downscale via Skia (targetWidth) — TIDAK di compute isolate:
      // ui.instantiateImageCodec butuh root isolate engine. Downscale saat
      // decode = alokasi RGBA ~3.7MB, bukan full-res ~48MB.
      final thumb = await genPostThumb(full);
      if (thumb != null) {
        _memPut(path, thumb);
        _writeFileAsync(folder, f, thumb);
      }
      return thumb;
    } catch (e) {
      dlog('[PostPhotoCache] thumb error: $e');
      return null;
    }
  }

  /// Ambil banyak thumbnail sekaligus — miss download paralel (maks 4).
  /// Return Map path → thumbBytes; yang gagal tidak masuk.
  Future<Map<String, Uint8List>> loadMany(List<String> paths) async {
    final result = <String, Uint8List>{};
    if (paths.isEmpty) return result;
    final missing = <String>[];
    for (final p in paths) {
      final mem = _memGet(p);
      if (mem != null) {
        result[p] = mem;
      } else {
        missing.add(p);
      }
    }
    if (missing.isEmpty) return result;

    // Paralel maks 4. `thumb()` men-dedupe via `_jobs`, jadi miss yang sama
    // dari kartu lain menunggu job yang sama (tidak ada path yang dilewati).
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final idx = next++;
        if (idx >= missing.length) return;
        final p = missing[idx];
        try {
          final t = await thumb(p);
          if (t != null) result[p] = t;
        } catch (_) {}
      }
    }

    await Future.wait(
      List.generate(missing.length.clamp(0, 4), (_) => worker()),
    );
    return result;
  }

  /// Ambil foto full-res (untuk viewer). Cek disk dulu; kalau miss, download
  /// dari Storage dan simpan ke disk supaya viewer berikutnya instan.
  /// Return base64 — format yang dipakai PhotoViewerScreen.fullLoader.
  Future<String?> full(String path) async {
    if (path.isEmpty) return null;
    try {
      final folder = await _folder();
      final f = _fullFileFor(folder, path);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        return base64Encode(bytes);
      }
      final full = await (downloader?.call(path) ?? Future<Uint8List?>.value());
      if (full == null) return null;
      _writeFileAsync(folder, f, full);
      return base64Encode(full);
    } catch (e) {
      dlog('[PostPhotoCache] full error: $e');
      return null;
    }
  }

  void _writeFileAsync(Directory folder, File f, Uint8List bytes) {
    // Fire-and-forget di background.
    Future(() async {
      try {
        await f.writeAsBytes(bytes, flush: true);
      } catch (_) {}
    });
  }

  /// Simpan foto post ke lokal (disk + memory) — dipanggil composer setelah
  /// upload sukses supaya feed yang baru di-refresh tampil instan tanpa
  /// re-download dari Storage. Pola sama dengan PhotoCache.save (chat).
  Future<Uint8List?> save(String path, Uint8List fullBytes) async {
    try {
      final thumb = await genPostThumb(fullBytes);
      if (thumb == null) return null;
      _memPut(path, thumb);
      final folder = await _folder();
      _writeFileAsync(folder, _fileFor(folder, path), thumb);
      return thumb;
    } catch (e) {
      dlog('[PostPhotoCache] save error: $e');
      return null;
    }
  }

  /// Bersihkan cache (dipanggil saat logout).
  Future<void> clearAll() async {
    _mem.clear();
    _memBytes = 0;
    try {
      final folder = await _folder();
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
    } catch (e) {
      dlog('[PostPhotoCache] clearAll ignored: $e');
    }
  }

  /// Purge cache disk yang basi + enforce quota (dipanggil saat startup).
  /// Tanpa ini, `post_photos_v2/*.jpg` tumbuh tanpa batas seiring scroll feed.
  /// - Hapus file lebih tua dari 14 hari.
  /// - Kalau total masih > 150 MB, hapus yang paling lama sampai di bawah.
  Future<void> cleanOldPhotos() async {
    try {
      final folder = await _folder();
      if (!await folder.exists()) return;
      final cutoff = DateTime.now().subtract(const Duration(days: 14));
      const maxBytes = 150 * 1024 * 1024;
      final files = <MapEntry<File, FileStat>>[];
      var total = 0;
      await for (final entity in folder.list()) {
        if (entity is! File) continue;
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          try {
            await entity.delete();
          } catch (_) {}
          continue;
        }
        files.add(MapEntry(entity, stat));
        total += stat.size;
      }
      if (total <= maxBytes) return;
      // Hapus tertua lebih dulu sampai di bawah quota.
      files.sort((a, b) => a.value.modified.compareTo(b.value.modified));
      for (final e in files) {
        if (total <= maxBytes) break;
        try {
          await e.key.delete();
          total -= e.value.size;
        } catch (_) {}
      }
    } catch (e) {
      dlog('[PostPhotoCache] cleanOldPhotos ignored: $e');
    }
  }
}
