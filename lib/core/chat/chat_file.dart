import 'package:flutter/material.dart';

/// Helper murni pesan FILE/dokumen (tanpa I/O): batas ukuran, mime, label
/// ukuran, dan gaya ikon per jenis file (ala WhatsApp).
class ChatFile {
  ChatFile._();

  /// Batas ukuran file chat (50 MB) — sama dengan batas storage service.
  static const int maxBytes = 50 * 1024 * 1024;

  /// Path file LOKAL milik pengirim (key = id pending ATAU path storage)
  /// → bubble bisa membuka file sendiri tanpa unduh ulang. Bounded 50.
  static final Map<String, String> _local = {};
  static void rememberLocal(String key, String path) {
    _local.remove(key);
    _local[key] = path;
    while (_local.length > 50) {
      _local.remove(_local.keys.first);
    }
  }

  static String? localPathOf(String key) => _local[key];
  static void forgetLocal(String key) => _local.remove(key);

  static String extOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  static const Map<String, String> _mime = {
    'pdf': 'application/pdf',
    'doc': 'application/msword',
    'docx':
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx':
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'txt': 'text/plain',
    'csv': 'text/csv',
    'zip': 'application/zip',
    'rar': 'application/vnd.rar',
    '7z': 'application/x-7z-compressed',
    'apk': 'application/vnd.android.package-archive',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'wav': 'audio/wav',
    'mp4': 'video/mp4',
    'mov': 'video/quicktime',
  };

  static String mimeOf(String name) =>
      _mime[extOf(name)] ?? 'application/octet-stream';

  /// "532 B", "12 KB", "1.4 MB".
  static String sizeLabel(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  }

  /// Ikon + warna per jenis file.
  static ({IconData icon, Color color}) styleOf(String name) {
    switch (extOf(name)) {
      case 'pdf':
        return (icon: Icons.picture_as_pdf_rounded, color: const Color(0xFFE53935));
      case 'doc':
      case 'docx':
      case 'txt':
        return (icon: Icons.description_rounded, color: const Color(0xFF1E88E5));
      case 'xls':
      case 'xlsx':
      case 'csv':
        return (icon: Icons.table_chart_rounded, color: const Color(0xFF43A047));
      case 'ppt':
      case 'pptx':
        return (icon: Icons.slideshow_rounded, color: const Color(0xFFFB8C00));
      case 'zip':
      case 'rar':
      case '7z':
        return (icon: Icons.folder_zip_rounded, color: const Color(0xFF8D6E63));
      case 'apk':
        return (icon: Icons.android_rounded, color: const Color(0xFF7CB342));
      case 'mp3':
      case 'm4a':
      case 'wav':
        return (icon: Icons.audiotrack_rounded, color: const Color(0xFFAB47BC));
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return (icon: Icons.image_rounded, color: const Color(0xFF26A69A));
      case 'mp4':
      case 'mov':
        return (icon: Icons.movie_rounded, color: const Color(0xFF5C6BC0));
      default:
        return (icon: Icons.insert_drive_file_rounded, color: const Color(0xFF78909C));
    }
  }
}
