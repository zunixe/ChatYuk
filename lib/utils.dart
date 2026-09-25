import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Log debug — di-strip total dari build release (kDebugMode=false →
/// compiler tree-shake pemanggilan). debugPrint di 150+ call site
/// sebelumnya tetap menyusun string + menulis log di produksi.
void dlog(String message, {String? tag}) {
  if (kDebugMode || kProfileMode) {
    debugPrint(tag == null ? message : '[$tag] $message');
  }
}

/// Kapitalkan huruf pertama pesan saat dikirim (gaya WhatsApp) — hanya bila
/// karakter pertama huruf kecil. Teks yang sudah mulai dengan simbol/emoji
/// atau sudah kapital dibiarkan apa adanya. Huruf setelah simbol pembuka
/// (mis. '"halo' → '"Halo') tidak disentuh agar tidak merusak format.
String capitalizeFirst(String text) {
  if (text.isEmpty) return text;
  final first = text[0];
  final upper = first.toUpperCase();
  if (first == upper) return text; // sudah kapital / simbol (emoji, tanda)
  if (!RegExp(r'[a-z]').hasMatch(first)) return text;
  return upper + text.substring(1);
}

DateTime parseDate(dynamic v) {
  if (v == null) return DateTime.now();
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
  return RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  ).hasMatch(email.trim());
}

/// Normalisasi nickname untuk cek larangan: lowercase + buang
/// spasi/underscore/dash supaya ZAINI-HAFID, ZAINI_HAFID, ZAINIHAFID sama.
String normalizeNicknameForBan(String nickname) {
  final lower = nickname.trim().toLowerCase();
  return lower.replaceAll(RegExp(r'[\s_\-]+'), '');
}

/// True bila nickname mengandung kata terlarang (substring, case-insensitive).
/// Daftar blokir: zaini, hafid — mencakup ZAINIHAFID dan kombinasinya.
bool isBannedNickname(String nickname) {
  final flat = normalizeNicknameForBan(nickname);
  if (flat.isEmpty) return false;
  return flat.contains('zaini') || flat.contains('hafid');
}

/// Validasi nickname — boleh huruf Unicode, angka, spasi, underscore, dash.
bool isValidNickname(String nickname) {
  final trimmed = nickname.trim();
  if (trimmed.isEmpty || trimmed.length < 3 || trimmed.length > 20)
    return false;
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
  0xFFE53935,
  0xFF1E88E5,
  0xFF43A047,
  0xFFFB8C00,
  0xFF8E24AA,
  0xFF00ACC1,
  0xFFD81B60,
  0xFF3949AB,
  0xFF689F38,
  0xFF6D4C41,
  0xFF546E7A,
  0xFFF4511E,
];

/// Format jam bubble chat — 12 jam + AM/PM (mis. "2:30 PM").
String formatBubbleTime(DateTime dt) {
  return DateFormat('h:mm a').format(dt.toLocal());
}

/// Format jam pesan — h:mm AM/PM.
/// Kalau pesan > hari ini, tampilkan tanggal juga.
String formatTime(DateTime dt) {
  final now = DateTime.now();
  final local = dt.toLocal();
  final todayStart = DateTime(now.year, now.month, now.day);
  final msgDay = DateTime(local.year, local.month, local.day);
  final diff = todayStart.difference(msgDay).inDays;

  if (diff == 0) {
    return DateFormat('h:mm a').format(local);
  } else if (diff == 1) {
    return 'Yesterday ${DateFormat('h:mm a').format(local)}';
  } else if (diff < 7) {
    return DateFormat('EEE h:mm a').format(local);
  } else {
    return DateFormat('d MMM h:mm a').format(local);
  }
}

/// Validasi bahwa string adalah base64 JPEG, PNG, atau WebP yang valid.
/// Header JPEG: /9j/ (base64 dari FF D8 FF)
/// Header PNG: iVBORw0KGgo (base64 dari 89 50 4E 47)
/// Header WebP: UklGR (base64 dari 52 49 46 46 — "RIFF")
bool isValidImageBase64(String b64) {
  if (b64.isEmpty) return false;
  final clean = b64.trim();
  return clean.startsWith('/9j/') || // JPEG
      clean.startsWith('iVBORw0KGgo') || // PNG
      clean.startsWith('UklGR'); // WebP
}

String formatRelativeTime(DateTime dt, {bool isId = false}) {
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inSeconds < 60) return isId ? 'Baru' : 'Now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat('d MMM').format(dt.toLocal());
}

/// Waktu ala kartu explore: 'Baru', '2 mnt', '14 mnt', '1 jam'.
String formatExploreTime(DateTime dt, {bool isId = false}) {
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inSeconds < 60) return isId ? 'Baru' : 'Now';
  if (diff.inMinutes < 60) {
    return isId ? '${diff.inMinutes} mnt' : '${diff.inMinutes} min';
  }
  if (diff.inHours < 24) {
    return isId ? '${diff.inHours} jam' : '${diff.inHours}h';
  }
  if (diff.inDays < 7) {
    return isId ? '${diff.inDays} hari' : '${diff.inDays}d';
  }
  return DateFormat('d MMM').format(dt.toLocal());
}

/// Angka ringkas ala kartu explore: 942 → '942', 1800 → '1.8rb', 3100 → '3.1rb'.
String formatCompactCount(int n, {bool isId = false}) {
  if (n < 1000) return '$n';
  final v = (n / 1000).toStringAsFixed(1).replaceAll('.0', '');
  return isId ? '${v}rb' : '${v}k';
}

int notifIdForKey(String key) {
  int hash = 0;
  for (int i = 0; i < key.length; i++) {
    hash = key.codeUnitAt(i) + ((hash << 5) - hash);
  }
  return hash.abs() & 0x7FFFFFFF;
}

final _snakeKeyCache = <String, Map<String, String>>{};

/// Konversi key snake_case (dari Postgres) → camelCase (untuk model Dart).
/// Cache hanya untuk mapping nama key (snake→camel), BUKAN nilai — tiap row
/// punya nilai berbeda, jadi cache seluruh Map<String, dynamic> akan merusak data.
Map<String, dynamic> snakeToCamel(Map<String, dynamic> map) {
  final keyStr = map.keys.join(',');
  final keyMap =
      _snakeKeyCache[keyStr] ??
      (() {
        final m = <String, String>{};
        for (final k in map.keys) {
          final parts = k.split('_');
          if (parts.length <= 1) {
            m[k] = k;
          } else {
            m[k] =
                parts.first +
                parts
                    .skip(1)
                    .where((p) => p.isNotEmpty)
                    .map((p) => p[0].toUpperCase() + p.substring(1))
                    .join();
          }
        }
        return _snakeKeyCache[keyStr] = m;
      })();
  return map.map((k, v) => MapEntry(keyMap[k] ?? k, v));
}

/// Rapikan list/poin di bubble chat saat render — berlaku untuk pesan
/// LAMA juga (server hanya merapikan balasan baru). Idempoten: baris yang
/// sudah rapi tidak berubah (aturan ≥2 butir PER BARIS + butir di awal
/// baris dihitung tapi tidak dipecah ulang). Isi blok kode ``` dilewati.
String formatChatLists(String src) {
  final out = <String>[];
  var inCode = false;
  final numCount = RegExp(r'(?:^|[^\S\n])\d{1,2}[.)]\s+(?=[A-Za-z])');
  final numSplit = RegExp(r'([^\S\n])(\d{1,2}[.)])(\s+)(?=[A-Za-z])');
  final parCount = RegExp(r'(?:^|[^\S\n])\([a-eA-E]\)\s+(?=[A-Za-z])');
  final parSplit = RegExp(r'([^\S\n])(\([a-eA-E]\))(\s+)(?=[A-Za-z])');
  final letCount = RegExp(r'(?:^|[^\S\n])[a-eA-E][.]\s+(?=[A-Za-z])');
  final letSplit = RegExp(r'([^\S\n])([a-eA-E][.])(\s+)(?=[A-Za-z])');
  for (final rawLine in src.split('\n')) {
    if (rawLine.trimLeft().startsWith('```')) {
      inCode = !inCode;
      out.add(rawLine);
      continue;
    }
    if (inCode) {
      out.add(rawLine);
      continue;
    }
    var cur = rawLine.replaceAll(RegExp(r'^\s*[•*]\s+'), '- ');
    if (numCount.allMatches(cur).length >= 2) {
      cur = cur.replaceAllMapped(numSplit, (m) => '\n\n${m[2]}${m[3]}');
    }
    if (parCount.allMatches(cur).length >= 2) {
      cur = cur.replaceAllMapped(parSplit, (m) => '\n  ${m[2]}${m[3]}');
    }
    if (letCount.allMatches(cur).length >= 2) {
      cur = cur.replaceAllMapped(letSplit, (m) => '\n  ${m[2]}${m[3]}');
    }
    out.add(cur);
  }
  return out.join('\n');
}

/// Format bytes ke bentuk mudah dibaca ("512 KB", "22.1 MB", "1.2 GB").
String formatBytes(num bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}

/// Format detik ke "mm:ss" (durasi call, voice note, timer banner).
/// Satu helper untuk seluruh app — dulu pola `padLeft(2,'0')` disalin di
/// 7+ tempat dengan varian yang tidak selalu konsisten.
String formatMmSs(int totalSeconds) {
  final s = totalSeconds < 0 ? 0 : totalSeconds;
  final m = (s ~/ 60).toString().padLeft(2, '0');
  final sec = (s % 60).toString().padLeft(2, '0');
  return '$m:$sec';
}
