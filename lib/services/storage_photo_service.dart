import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Penyimpanan foto chat di Supabase Storage.
/// DB hanya menyimpan PATH (mis. 'chat/<chatId>/<timestamp>.jpg'), bukan
/// base64 — menghemat ukuran DB drastis. Saat tampil, app download dari bucket.
///
/// Kompatibilitas: helper ini hanya menangani PATH. Base64 lama (sebelum
/// migrasi) tetap didukung — caller mengecek via [isPath].
class StoragePhotoService {
  /// Client opsional (LAZY) — test menyuntik client palsu.
  final SupabaseClient? _injected;
  StoragePhotoService._([SupabaseClient? sb]) : _injected = sb;

  static StoragePhotoService instance = StoragePhotoService._();

  @visibleForTesting
  factory StoragePhotoService.forTest(SupabaseClient sb) =>
      StoragePhotoService._(sb);

  @visibleForTesting
  static void overrideInstance(StoragePhotoService s) => instance = s;

  @visibleForTesting
  static void restoreInstance() => instance = StoragePhotoService._();

  static const _bucket = 'chat-photos';

  SupabaseClient get _sb => _injected ?? SupabaseConfig.client;

  bool isPath(String value) =>
      (value.startsWith('chat/') ||
          value.startsWith('posts/') ||
          value.startsWith('timeline/') ||
          value.startsWith('voice/')) &&
      (value.contains('.jpg') ||
          value.contains('.jpeg') ||
          value.contains('.png') ||
          value.contains('.m4a') ||
          value.contains('.mp3'));

  /// Path untuk foto baru di chat. Tidak bergantung messageId (yang baru
  /// diketahui setelah insert) — cukup chatId + timestamp unik.
  String newPath(String chatId) =>
      'chat/$chatId/${DateTime.now().microsecondsSinceEpoch}.jpg';

  /// Path avatar user. Versi pakai timestamp (cache-buster): path berubah
  /// tiap upload → device penonton & CDN Storage tidak lagi menyajikan
  /// file lama yang ter-cache (penyebab avatar terlihat "gepeng" versi lama
  /// setelah re-upload).
  String avatarPath(String uid) => 'avatars/$uid.jpg';

  /// Deteksi format gambar asli dari bytes (magic bytes), BUKAN dari nama
  /// file / asumsi. Mengembalikan ekstensi + MIME yang benar.
  ///
  /// Kenapa penting: avatar bisa di-upload sebagai WebP/PNG, tapi dulu path
  /// SELALU berakhiran `.jpg` dan upload TANPA `contentType`. Akibatnya file
  /// WebP disimpan bernama `.jpg` + dilabeli `image/jpeg` → device LAIN yang
  /// men-decode lewat CDN menerima content-type palsu → decode tidak sempurna
  /// (muncul artefak/"biro-biro"). Pemilik tetap melihat benar karena
  /// bytes asli sudah ter-cache lokal.
  static ({String ext, String mime}) _detectImageFormat(Uint8List b) {
    // JPEG: FF D8 FF
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return (ext: 'jpg', mime: 'image/jpeg');
    }
    // PNG: 89 50 4E 47
    if (b.length >= 4 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return (ext: 'png', mime: 'image/png');
    }
    // WebP: "RIFF" .... "WEBP"
    if (b.length >= 12 &&
        b[0] == 0x52 &&
        b[1] == 0x49 &&
        b[2] == 0x46 &&
        b[3] == 0x46 &&
        b[8] == 0x57 &&
        b[9] == 0x45 &&
        b[10] == 0x42 &&
        b[11] == 0x50) {
      return (ext: 'webp', mime: 'image/webp');
    }
    // Fallback: perlakukan sebagai JPEG (perilaku lama).
    return (ext: 'jpg', mime: 'image/jpeg');
  }

  /// Avatar versi unik per upload — dipakai untuk upload BARU.
  String avatarPathVersioned(String uid, {String ext = 'jpg'}) =>
      'avatars/${uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';

  /// Path foto galeri user (indeks/detik untuk keunikan).
  String photoPath(String uid) =>
      'gallery/$uid/${DateTime.now().microsecondsSinceEpoch}.jpg';

  /// Path foto post timeline.
  String postImagePath(String uid) =>
      'posts/$uid/${DateTime.now().microsecondsSinceEpoch}.jpg';

  /// Path foto story (slide).
  String storyPath(String uid) =>
      'story/$uid/${DateTime.now().microsecondsSinceEpoch}.jpg';

  /// Upload foto story → Storage. Return path atau null.
  Future<String?> uploadStoryImage({
    required String uid,
    required String base64,
  }) async {
    try {
      final bytes = base64Decode(base64);
      final path = storyPath(uid);
      await _sb.storage.from(_bucket).uploadBinary(path, bytes);
      return path;
    } catch (e) {
      dlog('[StoragePhoto] uploadStoryImage error: $e');
      return null;
    }
  }

  /// Path voice message.
  String voicePath(String chatId) =>
      'voice/$chatId/${DateTime.now().microsecondsSinceEpoch}.m4a';

  /// Upload foto post timeline → Storage. Return path atau null.
  Future<String?> uploadPostImage({
    required String uid,
    required String base64,
  }) async {
    try {
      final bytes = base64Decode(base64);
      final path = postImagePath(uid);
      await _sb.storage.from(_bucket).uploadBinary(path, bytes);
      return path;
    } catch (e) {
      dlog('[StoragePhoto] uploadPostImage error: $e');
      return null;
    }
  }

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
      dlog('[StoragePhoto] upload error: $e');
      return null;
    }
  }

  /// Upload voice m4a bytes → Storage. Return path atau null.
  Future<String?> uploadVoice({
    required String chatId,
    required Uint8List bytes,
  }) async {
    try {
      final path = voicePath(chatId);
      await _sb.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'audio/m4a'),
          );
      return path;
    } catch (e) {
      dlog('[StoragePhoto] uploadVoice error: $e');
      return null;
    }
  }

  bool isVoicePath(String v) => v.startsWith('voice/') && v.contains('.m4a');

  /// Download path → base64. Null jika gagal / tidak ditemukan.
  Future<String?> download(String path) async {
    try {
      final bytes = await _sb.storage.from(_bucket).download(path);
      if (bytes.isEmpty) return null;
      return base64Encode(bytes);
    } catch (e) {
      dlog('[StoragePhoto] download error: $e');
      return null;
    }
  }

  /// Download path → bytes mentah (untuk cache/thumbnail). Null jika gagal.
  Future<Uint8List?> downloadBytes(String path) async {
    try {
      final bytes = await _sb.storage.from(_bucket).download(path);
      if (bytes.isEmpty) return null;
      return bytes;
    } catch (e) {
      dlog('[StoragePhoto] downloadBytes error: $e');
      return null;
    }
  }

  /// Thumbnail kecil via transformasi server (jauh lebih ringan dari file
  /// full untuk tile 64px). Fallback ke download full kalau transform
  /// tidak didukung server — thumbnail tidak boleh gagal total.
  /// height/resize WAJIB diisi untuk hasil proporsional: server
  /// menghancurkan aspek bila hanya width tanpa resize (kasus nyata:
  /// story 960x1440 → 160x1440). Story tile 62x109: width 180 + height 316 +
  /// cover (rasio 0.569 = kartu preview viewer, crop thumbnail = preview).
  Future<Uint8List?> downloadThumbBytes(String path,
      {int width = 160,
      int? height,
      ResizeMode? resize,
      int quality = 70}) async {
    try {
      final bytes = await _sb.storage.from(_bucket).download(
            path,
            transform: TransformOptions(
              width: width,
              height: height,
              resize: resize,
              quality: quality,
            ),
          );
      if (bytes.isNotEmpty) return bytes;
    } catch (e) {
      dlog('[StoragePhoto] thumb transform gagal, fallback full: $e');
    }
    return downloadBytes(path);
  }

  /// Hapus foto dari Storage (logout/admin). Best-effort.
  Future<void> delete(String path) async {
    try {
      await _sb.storage.from(_bucket).remove([path]);
    } catch (e) {
      dlog('[StoragePhoto] delete error: $e');
    }
  }

  /// Upload avatar → Storage. Return path atau null.
  /// Path DIBERI TIMESTAMP — path baru tiap upload, mem-bypass cache CDN &
  /// cache device penonton (dulu: path tetap sama → re-upload tetap tampil
  /// versi lama di HP orang lain).
  Future<String?> uploadAvatar({
    required String uid,
    required String base64,
  }) async {
    try {
      final bytes = base64Decode(base64);
      // Ekstensi + contentType HARUS cocok dengan bytes asli. Kalau tidak,
      // device penonton men-decode lewat CDN dengan content-type palsu →
      // gambar tampil rusak (artefak). Lihat [_detectImageFormat].
      final fmt = _detectImageFormat(bytes);
      final path = avatarPathVersioned(uid, ext: fmt.ext);
      await _sb.storage
          .from(_bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: fmt.mime),
          );
      return path;
    } catch (e) {
      dlog('[StoragePhoto] uploadAvatar error: $e');
      return null;
    }
  }

  /// Upload foto galeri → Storage. Return path atau null.
  Future<String?> uploadPhoto({
    required String uid,
    required String base64,
  }) async {
    try {
      final bytes = base64Decode(base64);
      final path = photoPath(uid);
      await _sb.storage.from(_bucket).uploadBinary(path, bytes);
      return path;
    } catch (e) {
      dlog('[StoragePhoto] uploadPhoto error: $e');
      return null;
    }
  }

  /// Path storage bisa berupa path biasa atau base64? Deteksi.
  bool isAvatarPath(String v) => v.startsWith('avatars/');
  bool isGalleryPath(String v) => v.startsWith('gallery/');
}
