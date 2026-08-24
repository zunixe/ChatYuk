import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'storage_photo_service.dart';

// Top-level untuk compute() — buat thumbnail JPEG (~1024px) dari bytes asli.
// 512px terlihat blur saat foto single di-upscale selebar layar (1080px fisik).
Uint8List? _genPostThumb(Uint8List bytes) {
  try {
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    final thumb = img.copyResize(
      image,
      width: 1024,
      interpolation: img.Interpolation.linear,
    );
    return img.encodeJpg(thumb, quality: 82);
  } catch (_) {
    return null;
  }
}

/// Cache foto post timeline di DISK + MEMORY.
///
/// - File thumbnail (~1024px) disimpan sebagai JPEG biasa (foto post bersifat
///   publik, tidak perlu enkripsi seperti foto chat privat).
/// - Scroll ulang feed = baca disk (instan), TIDAK download ulang dari
///   Storage. Hanya miss pertama yang download full-res sekali, lalu
///   thumbnail dibuat di isolate.
class PostPhotoCache {
  PostPhotoCache._();
  static final PostPhotoCache instance = PostPhotoCache._();

  static const _folderName = 'post_photos_v2';

  // In-memory thumbnail (path → bytes JPEG). LRU sederhana, cap 30MB.
  final Map<String, Uint8List> _mem = {};
  static const _memMaxBytes = 30 * 1024 * 1024;
  int _memBytes = 0;

  // Path yang sedang di-download (dedupe panggilan paralel).
  final Set<String> _inflight = {};

  void _memPut(String path, Uint8List bytes) {
    _mem.remove(path);
    _mem[path] = bytes;
    _memBytes += bytes.length;
    while (_memBytes > _memMaxBytes && _mem.isNotEmpty) {
      final oldest = _mem.keys.first;
      _memBytes -= _mem.remove(oldest)!.length;
    }
  }

  Uint8List? _memGet(String path) => _mem[path];

  Future<Directory> _folder() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/$_folderName');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  File _fileFor(Directory folder, String path) =>
      File('${folder.path}/${path.hashCode}.jpg');

  // Full-res disimpan terpisah (suffix .full) supaya thumbnail & full bisa
  // punya umur berbeda dan tidak saling menimpa.
  File _fullFileFor(Directory folder, String path) =>
      File('${folder.path}/${path.hashCode}.full.jpg');

  /// Ambil thumbnail foto post. [path] adalah path storage (mis. `posts/uid/ts.jpg`).
  Future<Uint8List?> thumb(String path) async {
    if (path.isEmpty) return null;
    final mem = _memGet(path);
    if (mem != null) return mem;
    if (_inflight.contains(path)) return null;
    _inflight.add(path);
    try {
      final folder = await _folder();
      final f = _fileFor(folder, path);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        _memPut(path, bytes);
        return bytes;
      }
      final full = await StoragePhotoService.instance.downloadBytes(path);
      if (full == null) return null;
      final thumb = await compute(_genPostThumb, full);
      if (thumb != null) {
        _memPut(path, thumb);
        _writeFileAsync(folder, f, thumb);
      }
      return thumb;
    } catch (e) {
      debugPrint('[PostPhotoCache] thumb error: $e');
      return null;
    } finally {
      _inflight.remove(path);
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

    // Tandai semua path yang akan dikerjakan sebagai in-flight (dedupe),
    // dan pastikan SELALU dibersihkan di finally — kalau tidak, path yang
    // gagal akan stuck in-flight dan tidak pernah ditampilkan lagi.
    final claimed = <String>[];
    for (final p in missing) {
      if (!_inflight.contains(p)) {
        _inflight.add(p);
        claimed.add(p);
      }
    }
    try {
      // Batch: cek disk dulu untuk semua, sisanya download.
      final folder = await _folder();
      final toFetch = <String>[];
      for (final p in claimed) {
        final f = _fileFor(folder, p);
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          _memPut(p, bytes);
          result[p] = bytes;
        } else {
          toFetch.add(p);
        }
      }
      var next = 0;
      Future<void> worker() async {
        while (true) {
          final idx = next++;
          if (idx >= toFetch.length) return;
          final p = toFetch[idx];
          try {
            final full = await StoragePhotoService.instance.downloadBytes(p);
            if (full == null) continue;
            final thumb = await compute(_genPostThumb, full);
            if (thumb == null) continue;
            _memPut(p, thumb);
            _writeFileAsync(folder, _fileFor(folder, p), thumb);
            result[p] = thumb;
          } catch (_) {}
        }
      }

      await Future.wait(
        List.generate(toFetch.length.clamp(0, 4), (_) => worker()),
      );
    } catch (e) {
      debugPrint('[PostPhotoCache] loadMany error: $e');
    } finally {
      for (final p in claimed) {
        _inflight.remove(p);
      }
    }
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
      final full = await StoragePhotoService.instance.downloadBytes(path);
      if (full == null) return null;
      _writeFileAsync(folder, f, full);
      return base64Encode(full);
    } catch (e) {
      debugPrint('[PostPhotoCache] full error: $e');
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
      final thumb = await compute(_genPostThumb, fullBytes);
      if (thumb == null) return null;
      _memPut(path, thumb);
      final folder = await _folder();
      _writeFileAsync(folder, _fileFor(folder, path), thumb);
      return thumb;
    } catch (e) {
      debugPrint('[PostPhotoCache] save error: $e');
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
      debugPrint('[PostPhotoCache] clearAll ignored: $e');
    }
  }
}
