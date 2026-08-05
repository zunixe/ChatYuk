import 'package:intl/intl.dart';

DateTime parseDate(dynamic v) {
  if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
  if (v is DateTime) return v;
  if (v is String) {
    final dt = DateTime.tryParse(v);
    if (dt != null) return dt.toLocal();
  }
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  return DateTime.fromMillisecondsSinceEpoch(0);
}

/// Validasi format email — lebih strict dari sekedar cek @ dan .
bool isValidEmail(String email) {
  return RegExp(r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$')
      .hasMatch(email.trim());
}

/// Validasi nickname — boleh huruf Unicode, angka, spasi, underscore, dash.
bool isValidNickname(String nickname) {
  final trimmed = nickname.trim();
  if (trimmed.isEmpty || trimmed.length < 3 || trimmed.length > 20) return false;
  return RegExp(r'^[\p{L}\p{N} _\-]+$', unicode: true).hasMatch(trimmed);
}

int colorHashForUid(String uid) {
  int hash = 0;
  for (int i = 0; i < uid.length; i++) {
    hash = uid.codeUnitAt(i) + ((hash << 5) - hash);
  }
  return hash.abs();
}

const userColorPalette = [
  0xFFE53935, 0xFF1E88E5, 0xFF43A047, 0xFFFB8C00,
  0xFF8E24AA, 0xFF00ACC1, 0xFFD81B60, 0xFF3949AB,
  0xFF689F38, 0xFF6D4C41, 0xFF546E7A, 0xFFF4511E,
];

/// Format jam pesan — HH:mm.
/// Kalau pesan > hari ini, tampilkan tanggal juga.
String formatTime(DateTime dt) {
  final now = DateTime.now();
  final local = dt.toLocal();
  final todayStart = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(local.year, local.month, local.day);
  final diff = todayStart.difference(msgDay).inDays;

  if (diff == 0) {
    return DateFormat.Hm().format(local);
  } else if (diff == 1) {
    return 'Yesterday ${DateFormat.Hm().format(local)}';
  } else if (diff < 7) {
    return DateFormat('EEE HH:mm').format(local);
  } else {
    return DateFormat('d MMM HH:mm').format(local);
  }
}

/// Validasi bahwa string adalah base64 JPEG atau PNG yang valid.
/// Header JPEG: /9j/ (base64 dari FF D8 FF)
/// Header PNG: iVBORw0KGgo (base64 dari 89 50 4E 47)
bool isValidImageBase64(String b64) {
  if (b64.isEmpty) return false;
  final clean = b64.trim();
  return clean.startsWith('/9j/') || // JPEG
      clean.startsWith('iVBORw0KGgo'); // PNG
}
String formatRelativeTime(DateTime dt, {bool isId = false}) {
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inSeconds < 60) return isId ? 'Baru' : 'Now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat('d MMM').format(dt.toLocal());
}

int notifIdForKey(String key) {
  int hash = 0;
  for (int i = 0; i < key.length; i++) {
    hash = key.codeUnitAt(i) + ((hash << 5) - hash);
  }
  return hash.abs() & 0x7FFFFFFF;
}

/// Konversi key snake_case (dari Postgres) → camelCase (untuk model Dart).
Map<String, dynamic> snakeToCamel(Map<String, dynamic> map) {
  return map.map((k, v) {
    final parts = k.split('_');
    if (parts.length <= 1) return MapEntry(k, v);
    final camel = parts.first +
        parts.skip(1).where((p) => p.isNotEmpty)
            .map((p) => p[0].toUpperCase() + p.substring(1)).join();
    return MapEntry(camel, v);
  });
}
