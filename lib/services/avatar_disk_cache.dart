import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Cache DISK untuk foto profil/avatar — sumber kebenaran lokal.
///
/// Aturan (permintaan): avatar TIDAK disimpan sebagai source-of-truth di RAM.
/// - Load     → baca dari disk (instan, tanpa network)
/// - Update   → tulis ke server + tulis ke disk
/// - Tanpa perubahan → tetap baca dari disk
/// RAM hanya dipakai sebagai render-cache sesaat saat widget tampil.
///
/// Filename = hash deterministik dari serverPath (path Supabase versioned
/// per upload), jadi avatar baru = file baru → tidak ada masalah cache lama.
class AvatarDiskCache {
  AvatarDiskCache._();
  static final instance = AvatarDiskCache._();

  static const _dirName = 'avatar_cache';

  Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/$_dirName');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// FNV-1a 32-bit — deterministik antar run & antar device.
  String _fileName(String serverPath) {
    var h = 0x811c9dc5;
    for (final c in serverPath.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  Future<Uint8List?> read(String serverPath) async {
    if (serverPath.isEmpty) return null;
    try {
      final f = File('${(await _dir()).path}/${_fileName(serverPath)}');
      if (!f.existsSync()) return null;
      return f.readAsBytesSync();
    } catch (e) {
      debugPrint('[AvatarDisk] read error: $e');
      return null;
    }
  }

  Future<void> write(String serverPath, Uint8List bytes) async {
    if (serverPath.isEmpty || bytes.isEmpty) return;
    try {
      final f = File('${(await _dir()).path}/${_fileName(serverPath)}');
      await f.writeAsBytes(bytes, flush: true);
    } catch (e) {
      debugPrint('[AvatarDisk] write error: $e');
    }
  }

  /// Hapus semua file avatar yang TIDAK ada di daftar [activePaths] —
  /// dipanggil setelah sync agar disk tidak menumpuk file versi lama.
  Future<void> keepOnly(Set<String> activePaths) async {
    try {
      final active = activePaths.map(_fileName).toSet();
      final d = await _dir();
      await for (final f in d.list()) {
        if (f is! File) continue;
        if (!active.contains(f.uri.pathSegments.last)) {
          try {
            await f.delete();
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('[AvatarDisk] keepOnly error: $e');
    }
  }

  Future<void> clearAll() async {
    try {
      final d = await _dir();
      if (d.existsSync()) await d.delete(recursive: true);
    } catch (_) {}
  }
}
