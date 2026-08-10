import 'dart:io';
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
    try {
      final f = await _fileFor(chatKey, messageId);
      if (!await f.exists()) return null;
      return await MessageCache.instance.decryptString(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Simpan foto ke file lokal terenkripsi (sync dari server).
  Future<void> save(String chatKey, String messageId, String base64Image) async {
    final f = await _fileFor(chatKey, messageId);
    final enc = await MessageCache.instance.encryptString(base64Image);
    await f.writeAsString(enc, flush: true);
  }

  /// Hapus semua file foto (dipanggil saat logout).
  Future<void> clearAll() async {
    try {
      final folder = await _folder();
      if (await folder.exists()) {
        await folder.delete(recursive: true);
      }
    } catch (_) {}
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
    } catch (_) {}
  }
}
