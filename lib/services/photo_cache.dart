import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'message_cache.dart';

// Top-level untuk compute() — buat thumbnail JPEG kecil (~512px) dari base64.
Future<String?> _genThumb(Map<String, dynamic> args) async {
  try {
    final b64 = args['b64'] as String;
    final bytes = base64Decode(b64);
    final image = img.decodeImage(bytes);
    if (image == null) return null;
    final thumb = img.copyResize(
      image,
      width: 512,
      interpolation: img.Interpolation.linear,
    );
    final jpg = img.encodeJpg(thumb, quality: 75);
    return base64Encode(jpg);
  } catch (_) {
    return null;
  }
}

/// Cache foto pesan lokal sebagai FILE terenkripsi (AES-GCM, kunci dari
/// Android Keystore via MessageCache). Setiap foto satu file terpisah
/// sehingga buka chat cukup baca/decrypt foto yang tampil saja — cepat.
/// File tidak bisa dibuka langsung dari filesystem karena terenkripsi.
///
/// Bubble menampilkan THUMBNAIL kecil (~512px) yang dibuat saat foto masuk —
/// decode instan walau chat penuh foto. Full-res hanya dimuat saat user
/// membuka fullscreen.
class PhotoCache {
  PhotoCache._();
  static final PhotoCache instance = PhotoCache._();

  static const _folderName = 'chat_photos_v1';

  // In-memory cache full-res yang sudah didecrypt (messageId → b64).
  // Buka ulang chat = foto langsung muncul tanpa baca file + decrypt lagi.
  // Dibatasi 20MB — LRU sederhana, buang yang paling lama saat penuh.
  final Map<String, String> _memCache = {};
  static const _memMaxChars = 20 * 1024 * 1024;
  int _memChars = 0;

  // In-memory cache thumbnail (jauh lebih kecil — puluhan KB).
  final Map<String, String> _thumbMem = {};
  static const _thumbMemMaxChars = 8 * 1024 * 1024;
  int _thumbMemChars = 0;

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

  void _thumbPut(String messageId, String b64) {
    _thumbMem.remove(messageId);
    _thumbMem[messageId] = b64;
    _thumbMemChars += b64.length;
    while (_thumbMemChars > _thumbMemMaxChars && _thumbMem.isNotEmpty) {
      final oldest = _thumbMem.keys.first;
      _thumbMemChars -= _thumbMem.remove(oldest)!.length;
    }
  }

  String? _thumbGet(String messageId) => _thumbMem[messageId];

  Future<Directory> _folder() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/$_folderName');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  File _fileFor(Directory folder, String chatKey, String messageId) =>
      File('${folder.path}/${chatKey.hashCode}_$messageId.enc');

  File _thumbFileFor(Directory folder, String chatKey, String messageId) =>
      File('${folder.path}/${chatKey.hashCode}_${messageId}_thumb.enc');

  /// Baca foto FULL-RES dari file lokal (null jika belum ada / gagal decrypt).
  Future<String?> load(String chatKey, String messageId) async {
    final mem = _memGet(messageId);
    if (mem != null) return mem;
    try {
      final folder = await _folder();
      final f = _fileFor(folder, chatKey, messageId);
      if (!await f.exists()) return null;
      // Decrypt di background isolate agar UI tidak freeze saat load banyak foto
      final dec = await MessageCache.instance.decryptStringAsync(
        await f.readAsString(),
      );
      if (dec != null) _memPut(messageId, dec);
      return dec;
    } catch (_) {
      return null;
    }
  }

  /// Baca THUMBNAIL satu foto (untuk bubble / icon refresh).
  Future<String?> loadThumb(String chatKey, String messageId) async {
    final mem = _thumbGet(messageId);
    if (mem != null) return mem;
    try {
      final folder = await _folder();
      final tf = _thumbFileFor(folder, chatKey, messageId);
      if (await tf.exists()) {
        final dec = await MessageCache.instance.decryptStringAsync(
          await tf.readAsString(),
        );
        if (dec != null) _thumbPut(messageId, dec);
        return dec;
      }
      // Belum ada thumbnail (foto lama) → decrypt full, buat thumb, simpan.
      final f = _fileFor(folder, chatKey, messageId);
      if (!await f.exists()) return null;
      final full = await MessageCache.instance.decryptStringAsync(
        await f.readAsString(),
      );
      if (full == null) return null;
      final thumb = await compute(_genThumb, {'b64': full});
      if (thumb != null) {
        _thumbPut(messageId, thumb);
        _writeThumbFileAsync(chatKey, messageId, thumb);
        return thumb;
      }
      return full;
    } catch (_) {
      return null;
    }
  }

  /// Baca BANYAK thumbnail sekaligus untuk bubble — batch decrypt 1 isolate
  /// per batch. Hasil Map<messageId, thumbB64>; yang belum ada → tidak masuk.
  /// Foto lama (tanpa thumb) otomatis dibuatkan thumbnail-nya di sini.
  Future<Map<String, String>> loadMany(
    String chatKey,
    List<String> messageIds,
  ) async {
    final result = <String, String>{};
    if (messageIds.isEmpty) return result;
    final missing = <String>[];
    for (final id in messageIds) {
      final mem = _thumbGet(id);
      if (mem != null) {
        result[id] = mem;
      } else {
        missing.add(id);
      }
    }
    if (missing.isEmpty) return result;
    try {
      final folder = await _folder();
      final thumbPaths = <String, String>{};
      final fullPaths = <String, String>{};
      for (final id in missing) {
        final tf = _thumbFileFor(folder, chatKey, id);
        if (await tf.exists()) {
          thumbPaths[id] = tf.path;
          continue;
        }
        final ff = _fileFor(folder, chatKey, id);
        if (await ff.exists()) fullPaths[id] = ff.path;
      }
      // Thumbnail yang sudah ada — decrypt sekaligus (file kecil, super cepat).
      if (thumbPaths.isNotEmpty) {
        final dec = await MessageCache.instance.decryptMany(thumbPaths);
        if (dec != null) {
          dec.forEach((id, b64) {
            result[id] = b64;
            _thumbPut(id, b64);
          });
        }
      }
      // Foto lama (belum punya thumbnail): decrypt full → buat thumb →
      // simpan file thumb supaya buka berikutnya instan.
      if (fullPaths.isNotEmpty) {
        final dec = await MessageCache.instance.decryptMany(fullPaths);
        if (dec != null && dec.isNotEmpty) {
          final thumbs = await _genThumbsLimited(dec);
          for (final e in thumbs.entries) {
            result[e.key] = e.value;
            _thumbPut(e.key, e.value);
            _writeThumbFileAsync(chatKey, e.key, e.value);
          }
        }
      }
    } catch (e) {
      debugPrint('[PhotoCache] loadMany error: $e');
    }
    return result;
  }

  /// Generate thumbnail dari banyak foto — paralel (maks 5 isolate sekaligus).
  Future<Map<String, String>> _genThumbsLimited(
    Map<String, String> images,
  ) async {
    final result = <String, String>{};
    final entries = images.entries.toList();
    var next = 0;
    Future<void> worker() async {
      while (true) {
        final idx = next++;
        if (idx >= entries.length) return;
        final thumb = await compute(_genThumb, {'b64': entries[idx].value});
        if (thumb != null) result[entries[idx].key] = thumb;
      }
    }

    await Future.wait(
      List.generate(math.min(5, entries.length), (_) => worker()),
    );
    return result;
  }

  void _writeThumbFileAsync(String chatKey, String messageId, String thumbB64) {
    // Encrypt + tulis kecil & cepat — fire-and-forget di background.
    Future(() async {
      try {
        final folder = await _folder();
        final tf = _thumbFileFor(folder, chatKey, messageId);
        final enc = await MessageCache.instance.encryptString(thumbB64);
        await tf.writeAsString(enc, flush: true);
      } catch (_) {}
    });
  }

  /// Simpan foto full-res + buat thumbnail-nya. Mengembalikan thumbnail b64
  /// (untuk ditampilkan di bubble) atau null kalau gagal.
  Future<String?> save(
    String chatKey,
    String messageId,
    String base64Image,
  ) async {
    final folder = await _folder();
    final f = _fileFor(folder, chatKey, messageId);
    final enc = await MessageCache.instance.encryptString(base64Image);
    await f.writeAsString(enc, flush: true);
    _memPut(messageId, base64Image);
    final thumb = await compute(_genThumb, {'b64': base64Image});
    if (thumb != null) {
      _thumbPut(messageId, thumb);
      _writeThumbFileAsync(chatKey, messageId, thumb);
    }
    return thumb;
  }

  /// Hapus semua file foto (dipanggil saat logout).
  Future<void> clearAll() async {
    _memCache.clear();
    _memChars = 0;
    _thumbMem.clear();
    _thumbMemChars = 0;
    try {
      final folder = await _folder();
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('[PhotoCache] clearAll ignored: $e');
    }
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
    } catch (e) {
      debugPrint('[PhotoCache] clearAll ignored: $e');
    }
  }
}
