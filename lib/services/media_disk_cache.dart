import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Cache DISK untuk semua media dari Supabase Storage (avatar, galeri
/// profil, voice) — sumber kebenaran lokal.
///
/// Aturan: load dari disk (instan, tanpa network); update = tulis ke
/// server + tulis ke disk; RAM hanya render-cache sesaat.
///
/// Filename = hash FNV-1a dari serverPath (path Supabase versioned per
/// upload) → media baru = file baru, tidak pernah konflik cache lama.
/// Index `index.json` menyimpan {serverPath: lastAccess} untuk LRU.
///
/// Kuota: [maxBytes] LRU — file terlama akses dihapus saat penuh
/// (voice & galeri path-nya unik per item, butuh batas ukuran).
class MediaDiskCache {
  MediaDiskCache._();
  static final MediaDiskCache instance = MediaDiskCache._();

  static const _dirName = 'media_cache';
  static const _indexName = 'index.json';
  /// Kuota 250MB — cukup galeri + voice tanpa memenuhi storage.
  static const int maxBytes = 250 * 1024 * 1024;

  final Map<String, DateTime> _index = {};
  bool _indexLoaded = false;
  String? _docs;

  String _fileName(String serverPath) {
    var h = 0x811c9dc5;
    for (final c in serverPath.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  String _pathFor(String serverPath) =>
      '$_docs/$_dirName/${_fileName(serverPath)}';

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    _docs = docs.path;
    final d = Directory('$_docs/$_dirName');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

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
      debugPrint('[MediaDisk] index load error: $e');
    }
  }

  Future<void> _saveIndex() async {
    try {
      final f = File('$_docs/$_dirName/$_indexName');
      f.writeAsStringSync(
        jsonEncode(_index.map((k, v) => MapEntry(k, v.toIso8601String()))),
        flush: true,
      );
    } catch (e) {
      debugPrint('[MediaDisk] index save error: $e');
    }
  }

  /// Warm-up SEBELUM widget pertama render — simpan documents path supaya
  /// [readSync] (sinkron) bisa dipakai kapan pun setelah ini (anti-blink).
  Future<void> prewarm() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      _docs = docs.path;
      final d = Directory('$_docs/$_dirName');
      if (!d.existsSync()) d.createSync(recursive: true);
      await _loadIndex();
    } catch (e) {
      debugPrint('[MediaDisk] prewarm error: $e');
    }
  }

  Future<Uint8List?> read(String serverPath) async {
    if (serverPath.isEmpty) return null;
    try {
      await _dir();
      await _loadIndex();
      final f = File(_pathFor(serverPath));
      if (!f.existsSync()) return null;
      _index[serverPath] = DateTime.now();
      unawaited(_saveIndex());
      return f.readAsBytesSync();
    } catch (e) {
      debugPrint('[MediaDisk] read error: $e');
      return null;
    }
  }

  /// Baca SINKRON (file kecil seperti avatar) — foto tampil pada frame
  /// pertama tanpa async. Wajib [prewarm] pernah dipanggil sebelumnya.
  Uint8List? readSync(String serverPath) {
    if (serverPath.isEmpty || _docs == null) return null;
    try {
      final f = File(_pathFor(serverPath));
      if (!f.existsSync()) return null;
      return f.readAsBytesSync();
    } catch (e) {
      debugPrint('[MediaDisk] readSync error: $e');
      return null;
    }
  }

  /// File lokal untuk suatu serverPath (null jika belum ter-cache) —
  /// dipakai pemutar audio yang butuh DeviceFileSource.
  Future<File?> fileFor(String serverPath) async {
    if (serverPath.isEmpty) return null;
    await _dir();
    final f = File(_pathFor(serverPath));
    return f.existsSync() ? f : null;
  }

  Future<void> write(String serverPath, Uint8List bytes) async {
    if (serverPath.isEmpty || bytes.isEmpty) return;
    try {
      await _dir();
      await _loadIndex();
      await _enforceQuota(bytes.length);
      final f = File(_pathFor(serverPath));
      await f.writeAsBytes(bytes, flush: true);
      _index[serverPath] = DateTime.now();
      unawaited(_saveIndex());
    } catch (e) {
      debugPrint('[MediaDisk] write error: $e');
    }
  }

  /// LRU: hapus file dengan akses terlama sampai ada ruang untuk [incoming].
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
      if (total + incoming <= maxBytes) return;
      final byName = {
        for (final (f, len) in files) f.uri.pathSegments.last: (f, len),
      };
      final names = byName.keys.toList()
        ..sort((a, b) => (_index[_pathOf(a)] ?? DateTime(2000))
            .compareTo(_index[_pathOf(b)] ?? DateTime(2000)));
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
      _index.removeWhere((k, v) => !existing.contains(_fileName(k)));
      unawaited(_saveIndex());
    } catch (e) {
      debugPrint('[MediaDisk] quota error: $e');
    }
  }

  /// Rekonstruksi serverPath dari filename hash — butuh index terbalik.
  final Map<String, String> _fileNameToPath = {};
  String? _pathOf(String fileName) => _fileNameToPath[fileName];

  /// Daftarkan pemetaan path → filename (dipanggil tiap write/read index).
  void _track(String serverPath) =>
      _fileNameToPath[_fileName(serverPath)] = serverPath;

  /// Hapus semua file media yang TIDAK ada di [activePaths] — dipakai
  /// avatar (path versioned per upload → versi lama jadi sampah).
  Future<void> keepOnly(Set<String> activePaths) async {
    try {
      for (final p in activePaths) {
        _track(p);
      }
      final active = activePaths.map(_fileName).toSet();
      final d = Directory('$_docs/$_dirName');
      await for (final f in d.list()) {
        if (f is! File) continue;
        final name = f.uri.pathSegments.last;
        if (name == _indexName) continue;
        if (!active.contains(name)) {
          try {
            await f.delete();
          } catch (_) {}
          _index.removeWhere((k, v) => _fileName(k) == name);
        }
      }
      unawaited(_saveIndex());
    } catch (e) {
      debugPrint('[MediaDisk] keepOnly error: $e');
    }
  }

  Future<void> clearAll() async {
    try {
      final d = Directory('$_docs/$_dirName');
      if (d.existsSync()) await d.delete(recursive: true);
      _index.clear();
      _indexLoaded = false;
    } catch (_) {}
  }
}
