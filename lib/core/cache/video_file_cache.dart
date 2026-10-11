import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../utils.dart';
import 'media_disk_cache.dart';

/// Cache FILE video chat yang PERSISTEN (seperti voice di [MediaDiskCache]).
///
/// Masalah yang dipecahkan: video hasil rekam kamera "ngeload lagi" setiap
/// cold start. Voice langsung tampil karena bytes-nya tersimpan persisten di
/// `MediaDiskCache` (kuota 250MB, dokumen app). Video TIDAK BOLEH masuk kuota
/// itu (satu video s.d. 8MB akan meng-evict LRU → poster/foto/voice hilang).
/// Dulu video disimpan di `getTemporaryDirectory()` — direktori temp bisa
/// dibersihkan OS kapan saja → tidak persisten.
///
/// Solusi: direktori khusus `video_cache/` di documents (persisten) dengan
/// kuota SENDIRI 1GB + LRU. Sekali video dibuka/ditonton → tersimpan di sini
/// → cold start berikutnya langsung kebuka tanpa unduh ulang (persis voice).
///
/// Filename = hash FNV-1a stabil dari path storage ([mediaCacheFileName]) +
/// `.mp4` → stabil lintas restart (Dart `String.hashCode` TIDAK stabil, jadi
/// tidak dipakai). Index `index.json` menyimpan {path: lastAccess} untuk LRU.
///
/// Boundary: helper MURNI di `core/` — tanpa import `services/` maupun
/// `providers/` (gate `check_screen_boundary.sh`).
class VideoFileCache {
  VideoFileCache._();
  static final VideoFileCache instance = VideoFileCache._();

  static const _dirName = 'video_cache';
  static const _indexName = 'index.json';

  /// Kuota 1GB — video chat maks 8MB → ~100+ video tersimpan. LRU membuang
  /// yang paling lama tidak ditonton saat penuh.
  static const int maxBytes = 1024 * 1024 * 1024;

  /// Cap JUMLAH entri index (R6/R7) — sama pola MediaDiskCache._maxIndexEntries.
  /// Kuota byte saja tak membatasi jumlah entri: banyak video kecil (8MB)
  /// tetap bisa menumpuk ribuan entri index (path versioned per-upload) →
  /// `index.json` & map RAM membengkak. Buang entri terlama (Index-only;
  /// file-nya dibersihkan LRU byte).
  static const int _maxIndexEntries = 2000;

  final Map<String, DateTime> _index = {};
  // P2d: map terbalik filename→path (O(1) LRU; hindari O(N×M)).
  final Map<String, String> _fileNameToPath = {};
  bool _indexLoaded = false;
  String? _docs;

  /// True bila prewarm sudah jalan.
  bool get isReady => _docs != null;

  String _fileName(String serverPath) =>
      '${mediaCacheFileName(serverPath)}.mp4';

  String _pathFor(String serverPath) =>
      '$_docs/$_dirName/${_fileName(serverPath)}';

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    _docs = docs.path;
    final d = Directory('$_docs/$_dirName');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Warm-up SEBELUM widget pertama render — supaya [fileForSync] bisa
  /// dipakai kapan pun setelah ini.
  Future<void> prewarm() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      _docs = docs.path;
      final d = Directory('$_docs/$_dirName');
      if (!d.existsSync()) d.createSync(recursive: true);
      await _loadIndex();
    } catch (e) {
      dlog('[VideoCache] prewarm error: $e');
    }
  }

  /// Direktori cache video (persisten) — dipakai juga untuk menyimpan bitmap
  /// poster mentah (poster_bmp_*) agar cold start nol-decode.
  Future<Directory> cacheDir() async => _dir();

  Future<void> _loadIndex() async {
    if (_indexLoaded) return;
    _indexLoaded = true;
    try {
      final f = File('$_docs/$_dirName/$_indexName');
      if (!f.existsSync()) return;
      final map = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      map.forEach((k, v) {
        final t = DateTime.tryParse('$v');
        if (t != null) _index[k] = t;
      });
    } catch (e) {
      dlog('[VideoCache] index load error: $e');
    }
  }

  Timer? _saveDebounce;

  /// Tulis index ter-coalesce (maks 1 tulis per 2 dtk).
  void _scheduleSaveIndex() {
    if (_saveDebounce?.isActive == true) return;
    _saveDebounce = Timer(const Duration(seconds: 2), () {
      _saveDebounce = null;
      unawaited(_saveIndex());
    });
  }

  Future<void> _saveIndex() async {
    try {
      final f = File('$_docs/$_dirName/$_indexName');
      await f.writeAsString(
        jsonEncode(_index.map((k, v) => MapEntry(k, v.toIso8601String()))),
        flush: true,
      );
    } catch (e) {
      dlog('[VideoCache] index save error: $e');
    }
  }

  /// File video bila SUDAH tersimpan (sinkron, tanpa I/O berat) — null bila
  /// belum ada / disk belum siap. Dipakai bubble agar langsung kebuka.
  File? fileForSync(String serverPath) {
    if (serverPath.isEmpty || _docs == null) return null;
    try {
      final f = File(_pathFor(serverPath));
      if (!f.existsSync() || f.lengthSync() <= 0) return null;
      _index[serverPath] = DateTime.now();
      _scheduleSaveIndex();
      return f;
    } catch (_) {
      return null;
    }
  }

  /// File video bila sudah tersimpan (async — menunggu dir/index siap).
  Future<File?> fileFor(String serverPath) async {
    if (serverPath.isEmpty) return null;
    try {
      await _dir();
      await _loadIndex();
      final f = File(_pathFor(serverPath));
      if (!f.existsSync() || f.lengthSync() <= 0) return null;
      _index[serverPath] = DateTime.now();
      _scheduleSaveIndex();
      return f;
    } catch (e) {
      dlog('[VideoCache] fileFor error: $e');
      return null;
    }
  }

  /// Simpan bytes video ke cache persisten + tegakkan kuota LRU.
  /// Return file tersimpan, atau null bila gagal.
  Future<File?> put(String serverPath, Uint8List bytes) async {
    if (serverPath.isEmpty || bytes.isEmpty) return null;
    try {
      await _dir();
      await _loadIndex();
      await _enforceQuota(bytes.length);
      final f = File(_pathFor(serverPath));
      await f.writeAsBytes(bytes, flush: true);
      _index[serverPath] = DateTime.now();
      _scheduleSaveIndex();
      return f;
    } catch (e) {
      dlog('[VideoCache] put error: $e');
      return null;
    }
  }

  /// LRU: hapus file akses-terlama sampai ada ruang untuk [incoming].
  Future<void> _enforceQuota(int incoming) async {
    try {
      final d = Directory('$_docs/$_dirName');
      var total = 0;
      final files = <(File, int)>[];
      await for (final f in d.list()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        if (name == _indexName) continue;
        final len = f.lengthSync();
        total += len;
        files.add((f, len));
      }
      if (!mediaQuotaExceeded(total, incoming, maxBytes)) return;
      final byName = {
        for (final (f, len) in files) f.uri.pathSegments.last: (f, len),
      };
      // P2d (2026-10-11): map TERBALIK filename→serverPath dibangun SEKALI
      // (O(N)) — dulu `pathOf` loop seluruh _index per nama → O(N×M) sinkron
      // yang makin lambat saat cache besar.
      _fileNameToPath.clear();
      for (final k in _index.keys) {
        _fileNameToPath[_fileName(k)] = k;
      }
      final names = byName.keys.toList()
        ..sort((a, b) {
          final pa = _fileNameToPath[a];
          final pb = _fileNameToPath[b];
          final ta = pa == null
              ? DateTime(2000)
              : (_index[pa] ?? DateTime(2000));
          final tb = pb == null
              ? DateTime(2000)
              : (_index[pb] ?? DateTime(2000));
          return ta.compareTo(tb);
        });
      for (final name in names) {
        if (total + incoming <= maxBytes) break;
        final entry = byName[name];
        if (entry == null) continue;
        try {
          await entry.$1.delete();
          total -= entry.$2;
        } catch (_) {}
      }
      final existing = byName.keys.toSet();
      _index.removeWhere((k, _) => !existing.contains(_fileName(k)));
      // Cap jumlah entri index (R6/R7) — buang terlama dari INDEX saja.
      if (_index.length > _maxIndexEntries) {
        final removeCount = _index.length - _maxIndexEntries;
        final oldest = _index.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        for (var i = 0; i < removeCount; i++) {
          final k = oldest[i].key;
          _index.remove(k);
          _fileNameToPath.remove(_fileName(k));
        }
      }
      _scheduleSaveIndex();
      if (kDebugMode) {
        dlog('[VideoCache] LRU enforced, total=${total ~/ 1024}KB');
      }
    } catch (e) {
      dlog('[VideoCache] quota error: $e');
    }
  }

  /// Hapus satu entri (mis. pesan dihapus).
  Future<void> remove(String serverPath) async {
    try {
      await _dir();
      final f = File(_pathFor(serverPath));
      if (f.existsSync()) await f.delete();
      _index.remove(serverPath);
      _scheduleSaveIndex();
    } catch (_) {}
  }

  /// Hapus SELURUH cache video (test / logout / ganti akun).
  Future<void> clearAll() async {
    try {
      final d = Directory('$_docs/$_dirName');
      if (d.existsSync()) await d.delete(recursive: true);
      _index.clear();
      _indexLoaded = false;
    } catch (_) {}
  }
}
