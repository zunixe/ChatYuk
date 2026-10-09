import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../utils.dart';
import 'package:path_provider/path_provider.dart';
import '../media/native_image.dart';
import 'message_cache.dart';

// Thumbnail JPEG kecil (~512px) dari base64 — kini di NATIVE
// (`NativeImage.downscaleB64`, fallback Dart) supaya decode+encode tidak
// memakai heap Dart. Lihat lib/core/media/native_image.dart.
@visibleForTesting
Future<String?> genThumb(Map<String, dynamic> args) async {
  try {
    final b64 = args['b64'] as String;
    return await NativeImage.downscaleB64(b64, targetWidth: 512, quality: 75);
  } catch (_) {
    return null;
  }
}

/// Apakah memori LRU melebihi cap (buang tertua)? Murni & testable.
/// `chars` = total karakter b64; `cap` = batas karakter.
@visibleForTesting
bool chatMemShouldEvict(int chars, int cap) => chars > cap;

/// Batas memori cache chat (full-res 20MB, thumb 8MB) — diekspos untuk test.
@visibleForTesting
const int chatMemMaxChars = 20 * 1024 * 1024;
@visibleForTesting
const int chatThumbMemMaxChars = 8 * 1024 * 1024;

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

  // Indeks messageId → chatKey. RAM cache di-key messageId saja (agar
  // `loadMany` simpel), tapi dengan indeks ini `clearChat` bisa mem-purge
  // RAM satu chat dengan PRESISI (dulu hanya file disk yang terhapus, RAM
  // nyangkut sampai LRU menguap sendiri).
  final Map<String, String> _memChatOf = {};
  final Map<String, String> _thumbChatOf = {};

  void _memPut(String messageId, String b64, [String? chatKey]) {
    _memCache.remove(messageId);
    _memCache[messageId] = b64;
    if (chatKey != null) _memChatOf[messageId] = chatKey;
    _memChars += b64.length;
    while (chatMemShouldEvict(_memChars, _memMaxChars) &&
        _memCache.isNotEmpty) {
      final oldest = _memCache.keys.first;
      _memChars -= _memCache.remove(oldest)!.length;
      _memChatOf.remove(oldest);
    }
  }

  String? _memGet(String messageId) => _memCache[messageId];

  void _thumbPut(String messageId, String b64, [String? chatKey]) {
    _thumbMem.remove(messageId);
    _thumbMem[messageId] = b64;
    if (chatKey != null) _thumbChatOf[messageId] = chatKey;
    _thumbMemChars += b64.length;
    while (chatMemShouldEvict(_thumbMemChars, _thumbMemMaxChars) &&
        _thumbMem.isNotEmpty) {
      final oldest = _thumbMem.keys.first;
      _thumbMemChars -= _thumbMem.remove(oldest)!.length;
      _thumbChatOf.remove(oldest);
    }
  }

  String? _thumbGet(String messageId) => _thumbMem[messageId];

  /// Buang SEMUA foto/thumb dari RAM saja (file disk tetap). Dipakai saat OS
  /// memberi sinyal memory-pressure. Melepas semuanya mencegah GC storm —
  /// tapi WAJIB tahu konsekuensinya: buka chat berikutnya harus membaca +
  /// men-decode ULANG semua thumbnail dari disk (terukur 17MB alokasi /
  /// 372 LOS objects → GC blok 34ms → frame stall 200ms saat resume).
  /// Untuk background biasa pakai [trimHeavyCache] (thumb dipertahankan).
  void trimMemCache() {
    _memCache.clear();
    _memChars = 0;
    _memChatOf.clear();
    _thumbMem.clear();
    _thumbMemChars = 0;
    _thumbChatOf.clear();
  }

  /// Buang HANYA foto full-res (paling besar per entri), PERTAHANKAN thumb
  /// yang sedang dipakai bubble. Dipakai saat resume dari background:
  /// melepas memori besar tetap dilakukan, tapi buka chat berikutnya TIDAK
  /// perlu men-decode ulang thumbnail → tidak ada GC blok / frame stall.
  void trimHeavyCache() {
    _memCache.clear();
    _memChars = 0;
    _memChatOf.clear();
  }

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
    final t0 = DateTime.now();
    final mem = _memGet(messageId);
    if (mem != null) {
      dlog('[PHOTO-TIME] load mem-hit ${DateTime.now().difference(t0).inMilliseconds}ms');
      return mem;
    }
    try {
      final folder = await _folder();
      final f = _fileFor(folder, chatKey, messageId);
      if (!await f.exists()) return null;
      final t1 = DateTime.now();
      final raw = await f.readAsString();
      final t2 = DateTime.now();
      // Decrypt di background isolate agar UI tidak freeze saat load banyak foto
      final dec = await MessageCache.instance.decryptStringAsync(raw);
      final t3 = DateTime.now();
      dlog('[PHOTO-TIME] load disk file=${(raw.length / 1024).round()}KB '
          'read=${t2.difference(t1).inMilliseconds}ms '
          'decrypt=${t3.difference(t2).inMilliseconds}ms '
          'total=${t3.difference(t0).inMilliseconds}ms');
      if (dec != null) _memPut(messageId, dec, chatKey);
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
        if (dec != null) _thumbPut(messageId, dec, chatKey);
        return dec;
      }
      // Belum ada thumbnail (foto lama) → decrypt full, buat thumb, simpan.
      final f = _fileFor(folder, chatKey, messageId);
      if (!await f.exists()) return null;
      final full = await MessageCache.instance.decryptStringAsync(
        await f.readAsString(),
      );
      if (full == null) return null;
      final thumb = await genThumb({'b64': full});
      if (thumb != null) {
        _thumbPut(messageId, thumb, chatKey);
        _writeThumbFileAsync(chatKey, messageId, thumb);
        return thumb;
      }
      return full;
    } catch (_) {
      return null;
    }
  }

  /// Baca BANYAK thumbnail sekaligus untuk bubble — batch decrypt 1 isolate
  /// per batch. Hasil `Map<messageId, thumbB64>`; yang belum ada → tidak masuk.
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
            _thumbPut(id, b64, chatKey);
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
            _thumbPut(e.key, e.value, chatKey);
            _writeThumbFileAsync(chatKey, e.key, e.value);
          }
        }
      }
    } catch (e) {
      dlog('[PhotoCache] loadMany error: $e');
    }
    return result;
  }

  /// Generate thumbnail dari banyak foto — paralel (maks 5 sekaligus).
  /// Decode via Skia targetWidth (bukan compute isolate): ui.instantiateImageCodec
  /// butuh root isolate engine, dan downscale saat decode sudah cepat di native.
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
        final thumb = await genThumb({'b64': entries[idx].value});
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
    _memPut(messageId, base64Image, chatKey);
    final thumb = await genThumb({'b64': base64Image});
    if (thumb != null) {
      _thumbPut(messageId, thumb, chatKey);
      _writeThumbFileAsync(chatKey, messageId, thumb);
    }
    return thumb;
  }

  /// Hapus file foto SATU chat (dipanggil saat chat di-hard-delete admin).
  /// Nama file = `${chatKey.hashCode}_$messageId(.enc|_thumb.enc)` — prefix
  /// hash chatKey unik per chat. RAM (keyed messageId) dipurge presisi lewat
  /// indeks `_memChatOf`/`_thumbChatOf` supaya foto chat terhapus tidak
  /// nyangkut di memori.
  Future<void> clearChat(String chatKey) async {
    try {
      // RAM dulu (sinkron) — purge presisi via indeks chatKey.
      final memIds = _memChatOf.entries
          .where((e) => e.value == chatKey)
          .map((e) => e.key)
          .toList();
      for (final id in memIds) {
        _memChatOf.remove(id);
        final val = _memCache.remove(id);
        if (val != null) _memChars -= val.length;
      }
      final thumbIds = _thumbChatOf.entries
          .where((e) => e.value == chatKey)
          .map((e) => e.key)
          .toList();
      for (final id in thumbIds) {
        _thumbChatOf.remove(id);
        final val = _thumbMem.remove(id);
        if (val != null) _thumbMemChars -= val.length;
      }
      final folder = await _folder();
      if (!await folder.exists()) return;
      final prefix = '${chatKey.hashCode}_';
      await for (final entity in folder.list()) {
        if (entity is File) {
          final name = entity.path.split('/').last;
          if (name.startsWith(prefix)) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      dlog('[PhotoCache] clearChat ignored: $e');
    }
  }

  /// Hapus semua file foto (dipanggil saat logout).
  Future<void> clearAll() async {
    _memCache.clear();
    _memChars = 0;
    _memChatOf.clear();
    _thumbMem.clear();
    _thumbMemChars = 0;
    _thumbChatOf.clear();
    try {
      final folder = await _folder();
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
    } catch (e) {
      dlog('[PhotoCache] clearAll ignored: $e');
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
      dlog('[PhotoCache] clearAll ignored: $e');
    }
  }
}
