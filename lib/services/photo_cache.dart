import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'message_cache.dart';

/// Cache foto pesan lokal sebagai FILE terenkripsi (AES-GCM, kunci dari
/// Android Keystore via MessageCache). Setiap foto satu file terpisah
/// sehingga buka chat cukup baca/decrypt foto yang tampil saja — cepat.
/// File tidak bisa dibuka langsung dari filesystem karena terenkripsi.
class PhotoCache {
  PhotoCache._();
  static final PhotoCache instance = PhotoCache._();

  static const _folderName = 'chat_photos_v1';

  // In-memory cache foto yang sudah didecrypt (messageId → b64).
  // Buka ulang chat = foto langsung muncul tanpa baca file + decrypt lagi.
  // Dibatasi 20MB — LRU sederhana, buang yang paling lama saat penuh.
  final Map<String, String> _memCache = {};
  static const _memMaxChars = 20 * 1024 * 1024;
  int _memChars = 0;

  void _memPut(String messageId, String b64) {
    _memCache.remove(messageId);
    _memCache[messageId] = b64;
    _memChars += b64.length;
    while (_memChars > _memMaxChars && _memCache.isNotEmpty) {
      final oldest = _memCache.keys.first;
      _memChars -= _memCache.remove(oldest)!.length;
    }
  }

  String? _memGet(String messageId) => _memCache[messageId];

  Future<Directory> _folder() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/$_folderName');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  Future<File> _fileFor(String chatKey, String messageId) async {
    final folder = await _folder();
    return File('${folder.path}/${chatKey.hashCode}_$messageId.enc');
  }

  /// Baca foto dari file lokal (null jika belum ada / gagal decrypt).
  Future<String?> load(String chatKey, String messageId) async {
    final mem = _memGet(messageId);
    if (mem != null) return mem;
    try {
      final f = await _fileFor(chatKey, messageId);
      if (!await f.exists()) return null;
      // Decrypt di background isolate agar UI tidak freeze saat load banyak foto
      final dec = await MessageCache.instance.decryptStringAsync(await f.readAsString());
      if (dec != null) _memPut(messageId, dec);
      return dec;
    } catch (_) {
      return null;
    }
  }

  /// Baca BANYAK foto sekaligus — SATU isolate untuk semua file (jauh lebih
  /// cepat dari load() per foto). Hasil Map<messageId, b64>; foto yang belum
  /// ada di lokal tidak masuk hasil.
  Future<Map<String, String>> loadMany(String chatKey, List<String> messageIds) async {
    final result = <String, String>{};
    if (messageIds.isEmpty) return result;
    final missing = <String>[];
    for (final id in messageIds) {
      final mem = _memGet(id);
      if (mem != null) {
        result[id] = mem;
      } else {
        missing.add(id);
      }
    }
    if (missing.isEmpty) return result;
    try {
      final folder = await _folder();
      final paths = <String, String>{};
      for (final id in missing) {
        final f = File('${folder.path}/${chatKey.hashCode}_$id.enc');
        if (await f.exists()) paths[id] = f.path;
      }
      if (paths.isEmpty) return result;
      final dec = await MessageCache.instance.decryptMany(paths);
      if (dec != null) {
        dec.forEach((id, b64) {
          result[id] = b64;
          _memPut(id, b64);
        });
      }
    } catch (e) {
      debugPrint('[PhotoCache] loadMany error: $e');
    }
    return result;
  }

  /// Simpan foto ke file lokal terenkripsi (sync dari server).
  Future<void> save(String chatKey, String messageId, String base64Image) async {
    final f = await _fileFor(chatKey, messageId);
    final enc = await MessageCache.instance.encryptString(base64Image);
    await f.writeAsString(enc, flush: true);
    _memPut(messageId, base64Image);
  }

  /// Hapus semua file foto (dipanggil saat logout).
  Future<void> clearAll() async {
    _memCache.clear();
    _memChars = 0;
    try {
      final folder = await _folder();
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
    } catch (e) { debugPrint('[PhotoCache] clearAll ignored: $e'); }
  }

  /// Hapus foto lebih tua dari 7 hari — panggil sesekali (startup).
  Future<void> cleanOldPhotos() async {
    try {
      final folder = await _folder();
      if (!await folder.exists()) return;
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      await for (final entity in folder.list()) {
        if (entity is File) {
          final stat = await entity.stat();
          if (stat.modified.isBefore(cutoff)) {
            await entity.delete();
          }
        }
      }
    } catch (e) { debugPrint('[PhotoCache] clearAll ignored: $e'); }
  }
}
