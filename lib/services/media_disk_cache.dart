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

  String _fileName(String serverPath) {
    var h = 0x811c9dc5;
    for (final c in serverPath.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/$_dirName');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<void> _loadIndex() async {
    if (_indexLoaded) return;
    _indexLoaded = true;
    try {
      final f = File('${(await _dir()).path}/$_indexName');
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
      final f = File('${(await _dir()).path}/$_indexName');
      f.writeAsStringSync(
        jsonEncode(_index.map((k, v) => MapEntry(k, v.toIso8601String()))),
        flush: true,
      );
    } catch (e) {
      debugPrint('[MediaDisk] index save error: $e');
    }
  }

  Future<Uint8List?> read(String serverPath) async {
    if (serverPath.isEmpty) return null;
    await _loadIndex();
    try {
      final f = File('${(await _dir()).path}/${_fileName(serverPath)}');
      if (!f.existsSync()) return null;
      _index[serverPath] = DateTime.now();
      unawaited(_saveIndex());
      return f.readAsBytesSync();
    } catch (e) {
      debugPrint('[MediaDisk] read error: $e');
      return null;
    }
  }

  /// File lokal untuk suatu serverPath (null jika belum ter-cache) —
  /// dipakai pemutar audio yang butuh DeviceFileSource.
  Future<File?> fileFor(String serverPath) async {
    if (serverPath.isEmpty) return null;
    final f = File('${(await _dir()).path}/${_fileName(serverPath)}');
    return f.existsSync() ? f : null;
  }

  Future<void> write(String serverPath, Uint8List bytes) async {
    if (serverPath.isEmpty || bytes.isEmpty) return;
    await _loadIndex();
    try {
      await _enforceQuota(bytes.length);
      final f = File('${(await _dir()).path}/${_fileName(serverPath)}');
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
      final d = await _dir();
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
      // Urut LRU berdasarkan index (yang tak ada di index = paling basi).
      final byName = {
        for (final (f, len) in files) f.uri.pathSegments.last: (f, len),
      };
      final names = byName.keys.toList()
        ..sort((a, b) => (_index[a] ?? DateTime(2000))
            .compareTo(_index[b] ?? DateTime(2000)));
      for (final name in names) {
        if (total + incoming <= maxBytes) break;
        final entry = byName[name];
        if (entry == null) continue;
        try {
          await entry.$1.delete();
          total -= entry.$2;
        } catch (_) {}
      }
      // Buang entri index yang filenya sudah tak ada.
      final existing = byName.keys.toSet();
      _index.removeWhere((k, v) => !existing.contains(_fileName(k)));
      unawaited(_saveIndex());
    } catch (e) {
      debugPrint('[MediaDisk] quota error: $e');
    }
  }

  /// Hapus semua file media yang TIDAK ada di [activePaths] — dipakai
  /// avatar (path versioned per upload → versi lama jadi sampah).
  Future<void> keepOnly(Set<String> activePaths) async {
    try {
      final active = activePaths.map(_fileName).toSet();
      final d = await _dir();
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
      final d = await _dir();
      if (d.existsSync()) await d.delete(recursive: true);
      _index.clear();
      _indexLoaded = false;
    } catch (_) {}
  }
}
