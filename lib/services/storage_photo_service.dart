import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Penyimpanan foto chat di Supabase Storage.
/// DB hanya menyimpan PATH (mis. 'chat/<chatId>/<timestamp>.jpg'), bukan
/// base64 — menghemat ukuran DB drastis. Saat tampil, app download dari bucket.
///
/// Kompatibilitas: helper ini hanya menangani PATH. Base64 lama (sebelum
/// migrasi) tetap didukung — caller mengecek via [isPath].
class StoragePhotoService {
  StoragePhotoService._();
  static final StoragePhotoService instance = StoragePhotoService._();

  static const _bucket = 'chat-photos';

  SupabaseClient get _sb => SupabaseConfig.client;

  bool isPath(String value) =>
      value.startsWith('chat/') && value.contains('.jpg');

  /// Path untuk foto baru di chat. Tidak bergantung messageId (yang baru
  /// diketahui setelah insert) — cukup chatId + timestamp unik.
  String newPath(String chatId) =>
      'chat/$chatId/${DateTime.now().microsecondsSinceEpoch}.jpg';

  /// Path avatar user.
  String avatarPath(String uid) => 'avatars/$uid.jpg';

  /// Path foto galeri user (indeks/detik untuk keunikan).
  String photoPath(String uid) =>
      'gallery/$uid/${DateTime.now().microsecondsSinceEpoch}.jpg';

  /// Upload base64 JPEG → Storage. Return path atau null jika gagal.
  Future<String?> upload({
    required String chatId,
    required String base64,
  }) async {
    try {
      final bytes = base64Decode(base64);
      final path = newPath(chatId);
      await _sb.storage.from(_bucket).uploadBinary(path, bytes);
      return path;
    } catch (e) {
      debugPrint('[StoragePhoto] upload error: $e');
      return null;
    }
  }

  /// Download path → base64. Null jika gagal / tidak ditemukan.
  Future<String?> download(String path) async {
    try {
      final bytes = await _sb.storage.from(_bucket).download(path);
      if (bytes.isEmpty) return null;
      return base64Encode(bytes);
    } catch (e) {
      debugPrint('[StoragePhoto] download error: $e');
      return null;
    }
  }

  /// Hapus foto dari Storage (logout/admin). Best-effort.
  Future<void> delete(String path) async {
    try {
      await _sb.storage.from(_bucket).remove([path]);
    } catch (e) {
      debugPrint('[StoragePhoto] delete error: $e');
    }
  }

  /// Upload avatar → Storage. Return path atau null.
  Future<String?> uploadAvatar({required String uid, required String base64}) async {
    try {
      final bytes = base64Decode(base64);
      final path = avatarPath(uid);
      await _sb.storage.from(_bucket).uploadBinary(
        path,
        bytes,
        fileOptions: const FileOptions(upsert: true),
      );
      return path;
    } catch (e) {
      debugPrint('[StoragePhoto] uploadAvatar error: $e');
      return null;
    }
  }

  /// Upload foto galeri → Storage. Return path atau null.
  Future<String?> uploadPhoto({required String uid, required String base64}) async {
    try {
      final bytes = base64Decode(base64);
      final path = photoPath(uid);
      await _sb.storage.from(_bucket).uploadBinary(path, bytes);
      return path;
    } catch (e) {
      debugPrint('[StoragePhoto] uploadPhoto error: $e');
      return null;
    }
  }

  /// Path storage bisa berupa path biasa atau base64? Deteksi.
  bool isAvatarPath(String v) => v.startsWith('avatars/');
  bool isGalleryPath(String v) => v.startsWith('gallery/');
}
