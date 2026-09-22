import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/connectivity_provider.dart';

/// Kategori kegagalan operasi admin.
///
/// TUJUAN: pesan mentah dari exception TIDAK BOLEH sampai ke layar. Saat
/// offline, `e.toString()` berisi hal internal seperti
/// `ClientException with SocketException: Failed host lookup:
/// 'fohcucyyejdryryoxitm.supabase.co'` — membocorkan URL project Supabase dan
/// membingungkan admin. Detail asli tetap dicatat lewat `dlog` (jejak debug
/// tidak hilang), sementara layar hanya menampilkan kategori yang ramah.
///
/// CATATAN BUILD: file ini hanya boleh di-import oleh modul admin. String-nya
/// DILETAKKAN di string_`admin_err_text.dart` (extension on S) supaya tree
/// shaker tetap membuang seluruh teks admin dari build rilis user.
enum AdminErrKind {
  /// Tidak ada internet / DNS gagal / timeout (kasus paling sering).
  offline,

  /// Sesi admin tidak valid (token kedaluwarsa, RPC guard menolak).
  unauthorized,

  /// Server merespons error (5xx) — bukan masalah koneksi user.
  server,

  /// Sisanya (parsing, bug, dll).
  unknown,
}

/// Klasifikasi exception apa pun menjadi [AdminErrKind].
AdminErrKind classifyAdminError(Object? e) {
  if (e == null) return AdminErrKind.unknown;

  if (e is SocketException) return AdminErrKind.offline;
  if (e is TimeoutException) return AdminErrKind.offline;
  if (e is HttpException) return AdminErrKind.server;

  if (e is PostgrestException) {
    final code = '${e.code ?? ''}';
    final msg = e.message.toLowerCase();
    // Guard RPC admin melempar 'Unauthorized' (P0001) — itu sesi, bukan koneksi.
    if (msg.contains('unauthorized') || msg.contains('forbidden')) {
      return AdminErrKind.unauthorized;
    }
    if (code.startsWith('5')) return AdminErrKind.server;
    if (code == '401' || code == '403') return AdminErrKind.unauthorized;
    return AdminErrKind.unknown;
  }

  if (e is AuthException) return AdminErrKind.unauthorized;

  // ClientException Supabase membungkus SocketException — pesannya string.
  final s = e.toString().toLowerCase();
  if (s.contains('socketexception') ||
      s.contains('failed host lookup') ||
      s.contains('clientexception') ||
      s.contains('connection refused') ||
      s.contains('network is unreachable') ||
      s.contains('connection closed') ||
      s.contains('timed out') ||
      s.contains('timeout')) {
    return AdminErrKind.offline;
  }
  if (s.contains('unauthorized') || s.contains('forbidden')) {
    return AdminErrKind.unauthorized;
  }
  return AdminErrKind.unknown;
}

/// True bila kategori ini berarti masalah koneksi (dipakai banner stale).
bool adminErrIsOffline(AdminErrKind? k) => k == AdminErrKind.offline;

/// Guard aksi TULIS admin saat offline.
///
/// Aksi admin (hapus user, ubah status dummy, simpan setting) TIDAK BOLEH
/// dijalankan tanpa koneksi: hasilnya gagal separuh jalan dan bisa
/// membingungkan (UI optimistis berubah padahal server tidak menerima).
/// Return `true` = aksi DIBLOKIR (dan sudah menampilkan pesan ke user).
bool blockIfOffline(
  bool online,
  void Function(String message) notify, {
  required String message,
}) {
  if (online) return false;
  notify(message);
  return true;
}

/// Versi ringkas untuk layar admin: baca konektivitas dari [context].
/// [notify] menerima teks pesan siap-tampil (mis. SnackBar/toast).
bool guardOfflineCtx(
  BuildContext context,
  String message,
  void Function(String message) notify,
) {
  bool online = true;
  try {
    online = Provider.of<ConnectivityProvider>(
      context,
      listen: false,
    ).online;
  } catch (_) {
    // Provider tidak tersedia (test/preview) → jangan blokir.
  }
  return blockIfOffline(online, notify, message: message);
}
