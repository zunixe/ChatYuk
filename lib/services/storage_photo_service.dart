import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart';
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

  /// Ikon room global upload-an (bukan emoji): `room-icons/<uid>/<file>`.
  /// Dipakai RoomIcon untuk memilih render gambar vs emoji/glyph.
  bool isRoomIconPath(String value) =>
      value.startsWith('room-icons/') &&
      (value.contains('.jpg') ||
          value.contains('.jpeg') ||
          value.contains('.png') ||
          value.contains('.webp'));

  bool isPath(String value) =>
      (value.startsWith('chat/') ||
          value.startsWith('posts/') ||
          value.startsWith('timeline/') ||
          value.startsWith('voice/') ||
          value.startsWith('story/') ||
          value.startsWith('room-icons/')) &&
      (value.contains('.jpg') ||
          value.contains('.jpeg') ||
          value.contains('.png') ||
          value.contains('.m4a') ||
          value.contains('.mp3') ||
          // VIDEO (chat + story) — tanpa ini path .mp4 dikira base64 →
          // bubble video gagal total (bukan "belum termuat").
          value.contains('.mp4') ||
          value.contains('.mov'));

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

  /// Path video story (slide mp4, maks 15 dtk).
  String storyVideoPath(String uid) =>
      'story/$uid/${DateTime.now().microsecondsSinceEpoch}.mp4';

  /// Upload video story → Storage. Return path atau null.
  Future<String?> uploadStoryVideo({
    required String uid,
    required Uint8List bytes,
  }) async {
    try {
      if (bytes.isEmpty) return null;
      final path = storyVideoPath(uid);
      await _sb.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'video/mp4'),
          );
      return path;
    } catch (e) {
      dlog('[StoragePhoto] uploadStoryVideo error: $e');
      return null;
    }
  }

  /// True bila path video story (`story/....mp4`).
  bool isStoryVideoPath(String v) =>
      v.startsWith('story/') && v.contains('.mp4');

  /// Kompres video story → 720p hemat (±1,5 Mbps, ~3 MB per 15 dtk).
  /// Return file hasil (di direktori cache) atau null bila gagal —
  /// pemanggil pakai file asli hanya bila kompresi gagal dan masih di
  /// bawah cap? TIDAK: gagal kompres = tolak (jangan upload mentah 20 MB).
  Future<File?> compressStoryVideo(
    String srcPath, {
    void Function(double progress01)? onProgress,
    int? startMs,
    int? durationMs,
  }) async {
    try {
      Subscription? sub;
      if (onProgress != null) {
        sub = VideoCompress.compressProgress$.subscribe((p) {
          onProgress((p.toDouble() / 100).clamp(0.0, 1.0));
        });
      }
      final info = await VideoCompress.compressVideo(
        srcPath,
        quality: VideoQuality.Res1280x720Quality,
        deleteOrigin: false,
        includeAudio: true,
        // 24fps (dulu 30): story adalah tontonan singkat, mata tak bedakan
        // 24 vs 30 di konten pendek — bitrate & ukuran file turun ~20% tanpa
        // terlihat lebih patah. Resolusi tetap 720p (tajam).
        frameRate: 24,
        // Potong segmen (video galeri panjang → beberapa story 15 dtk).
        startTime: startMs,
        duration: durationMs,
      ).timeout(const Duration(seconds: 180));
      sub?.unsubscribe();
      final f = info?.file;
      if (f == null || !await f.exists()) return null;
      return f;
    } catch (e) {
      dlog('[StoragePhoto] compressStoryVideo error: $e');
      return null;
    }
  }

  /// Satu frame poster JPEG untuk thumbnail tray story video.
  /// Pakai getFileThumbnail bawaan video_compress (paket video_thumbnail
  /// terpisah merusak build AGP 9). Server membuat thumb 180x316-nya.
  Future<Uint8List?> storyVideoPoster(String videoPath) async {
    // 1) Byte langsung (paling andal — tanpa file perantara).
    try {
      final bytes = await VideoCompress.getByteThumbnail(
        videoPath,
        quality: 70,
        position: 500,
      ).timeout(const Duration(seconds: 30));
      if (bytes != null && bytes.isNotEmpty) return bytes;
    } catch (e) {
      dlog('[StoragePhoto] poster byte thumb error: $e');
    }
    // 2) Fallback: file thumb (posisi 0 bila 500ms tak tersedia).
    try {
      final thumb = await VideoCompress.getFileThumbnail(
        videoPath,
        quality: 70,
        position: -1,
      ).timeout(const Duration(seconds: 30));
      final bytes = await thumb.readAsBytes();
      return bytes.isEmpty ? null : bytes;
    } catch (e) {
      dlog('[StoragePhoto] storyVideoPoster error: $e');
      return null;
    }
  }

  // ── VIDEO CHAT ── (private chat; room menyusul)
  /// Batas ukuran hasil kompres video chat (8 MB) — sama dengan foto.
  static const int chatVideoMaxBytes = 8 * 1024 * 1024;

  /// Batas durasi video chat (60 detik).
  static const int chatVideoMaxMs = 60 * 1000;

  /// Frame rate kompres video chat (24fps — dulu 30). Dikunci sebagai
  /// konstanta supaya kontrak "video chat ≤24fps" bisa di-unit-test tanpa
  /// plugin native. 24 tetap mulus di klip pendek, ukuran file ~20% lebih
  /// kecil dari 30fps.
  @visibleForTesting
  static const int chatVideoFrameRate = 24;

  /// Path video chat. Pola sama [newPath] (chatId + timestamp, tanpa
  /// messageId yang baru diketahui setelah insert).
  String chatVideoPath(String chatId) =>
      'chat/$chatId/${DateTime.now().microsecondsSinceEpoch}.mp4';

  /// True bila path video chat (`chat/....mp4`).
  bool isChatVideoPath(String v) =>
      v.startsWith('chat/') && (v.contains('.mp4') || v.contains('.mov'));

  /// Upload video chat → Storage. Return path atau null.
  Future<String?> uploadChatVideo({
    required String chatId,
    required Uint8List bytes,
  }) async {
    try {
      if (bytes.isEmpty) return null;
      final path = chatVideoPath(chatId);
      await _sb.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'video/mp4'),
          );
      return path;
    } catch (e) {
      dlog('[StoragePhoto] uploadChatVideo error: $e');
      return null;
    }
  }

  /// Kompres video chat → 480p hemat (target ±1 Mbps, ±7 MB per 60 dtk).
  /// Return file hasil atau null bila gagal. Gagal kompres = tolak
  /// (jangan upload mentah — boros kuota + bisa lewat batas 20 MB guard).
  Future<File?> compressChatVideo(
    String srcPath, {
    void Function(double progress01)? onProgress,
  }) async {
    try {
      Subscription? sub;
      if (onProgress != null) {
        sub = VideoCompress.compressProgress$.subscribe((p) {
          onProgress((p.toDouble() / 100).clamp(0.0, 1.0));
        });
      }
      final info = await VideoCompress.compressVideo(
        srcPath,
        quality: VideoQuality.Res640x480Quality,
        deleteOrigin: false,
        includeAudio: true,
        // 24fps (dulu 30): video chat pendek (≤60 dtk) — 24 tetap mulus di
        // mata, bitrate & ukuran file turun ~20% (hemat kuota & storage).
        frameRate: chatVideoFrameRate,
      ).timeout(const Duration(seconds: 240));
      sub?.unsubscribe();
      final f = info?.file;
      if (f == null || !await f.exists()) return null;
      return f;
    } catch (e) {
      dlog('[StoragePhoto] compressChatVideo error: $e');
      return null;
    }
  }

  /// Durasi video (ms) via metadata video_compress — 0 bila gagal dibaca.
  Future<int> videoDurationMs(String srcPath) async {
    try {
      final info = await VideoCompress.getMediaInfo(
        srcPath,
      ).timeout(const Duration(seconds: 20));
      return ((info.duration ?? 0).toDouble()).round();
    } catch (e) {
      dlog('[StoragePhoto] videoDurationMs error: $e');
      return 0;
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

  /// Path ikon room global. Folder = uid pembuat (syarat policy
  /// storage_object_owner_ok cabang room-icons).
  String roomIconPath(String uid, {String ext = 'jpg'}) =>
      'room-icons/$uid/${DateTime.now().microsecondsSinceEpoch}.$ext';

  /// Upload ikon room global → Storage. Return path atau null jika gagal.
  /// Dipanggil SEBELUM create (path disimpan di rooms.icon).
  Future<String?> uploadRoomIcon({
    required String uid,
    required String base64,
  }) async {
    try {
      final bytes = base64Decode(base64);
      final fmt = _detectImageFormat(bytes);
      final path = roomIconPath(uid, ext: fmt.ext);
      await _sb.storage
          .from(_bucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: fmt.mime),
          );
      return path;
    } catch (e) {
      dlog('[StoragePhoto] uploadRoomIcon error: $e');
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

  // Timeout sentral download: tanpa ini, koneksi stall menggantung
  // selamanya → foto "ketuk untuk memuat" tak pernah selesai (kasus nyata:
  // monitor admin 9436). Timeout → null → pemanggil bisa retry.
  static const _dlTimeout = Duration(seconds: 30);

  /// Download path → base64. Null jika gagal / tidak ditemukan.
  Future<String?> download(String path) async {
    try {
      final bytes = await _sb.storage
          .from(_bucket)
          .download(path)
          .timeout(_dlTimeout);
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
      final bytes = await _sb.storage
          .from(_bucket)
          .download(path)
          .timeout(_dlTimeout);
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
      final bytes = await _sb.storage
          .from(_bucket)
          .download(
            path,
            transform: TransformOptions(
              width: width,
              height: height,
              resize: resize,
              quality: quality,
            ),
          )
          .timeout(_dlTimeout);
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
  bool isStoryPath(String v) => v.startsWith('story/');
}
