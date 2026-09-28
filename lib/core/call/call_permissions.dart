import 'package:permission_handler/permission_handler.dart';

import '../../config/strings.dart';
import '../../utils.dart';

/// Penyebab spesifik kegagalan setup media (getUserMedia/createPeerConnection).
/// Dipakai UI supaya pesan yang tampil akurat, bukan "gagal terhubung" generik
/// untuk semua kasus.
enum CallMediaError {
  /// Izin kamera/mikrofon ditolak (NotAllowedError / SecurityError).
  permission,

  /// Kamera/mikrofon sedang dipakai aplikasi lain (NotReadableError / TrackStartError).
  inUse,

  /// Perangkat tidak punya kamera/mikrofon, atau constraint tak terpenuhi.
  notFound,

  /// Sebab lain (network, internal WebRTC, dsb).
  other,
}

/// Hasil permintaan izin kamera/mikrofon sebelum memulai panggilan.
///
/// Android/iOS mewajibkan izin **runtime** untuk kamera & mikrofon — manifest
/// saja TIDAK cukup. Sebelum ini `getUserMedia` dipanggil tanpa meminta izin,
/// sehingga panggilan pertama (izin belum ada) langsung gagal senyap:
/// `getUserMedia` melempar → `CallPhase.error` → user melihat "panggilan gagal"
/// tanpa penjelasan.
enum CallPermissionResult {
  /// Semua izin yang dibutuhkan sudah diberikan → aman lanjut `startSession`.
  granted,

  /// User menolak (masih bisa ditanya ulang / dialog OS muncul lagi).
  denied,

  /// User menolak permanen ("Jangan tanya lagi") → hanya bisa dipulihkan
  /// lewat Pengaturan aplikasi. UI wajib menawarkan tombol "Buka Pengaturan".
  permanentlyDenied,
}

/// Minta izin kamera (bila video) + mikrofon sebelum panggilan dimulai.
///
/// Dipanggil di tiga titik masuk: caller dari chat, caller dari profil user,
/// dan callee saat menerima (video call juga butuh kamera).
///
/// Best-effort & non-blocking UI: paket `permission_handler` menampilkan
/// dialog sistem bila izin belum pernah diminta.
Future<CallPermissionResult> ensureCallPermissions({
  required bool video,
}) async {
  try {
    final needed = <Permission>[
      Permission.microphone,
      if (video) Permission.camera,
    ];
    final statuses = await needed.request();
    dlog('[CALL-PERM] request video=$video -> $statuses');

    // Permanen di salah satu izin wajib → arahkan ke Pengaturan.
    for (final p in needed) {
      final st = statuses[p];
      if (st == PermissionStatus.permanentlyDenied ||
          st == PermissionStatus.restricted) {
        return CallPermissionResult.permanentlyDenied;
      }
    }
    // Semua harus granted untuk lanjut.
    for (final p in needed) {
      final st = statuses[p];
      if (st != PermissionStatus.granted &&
          st != PermissionStatus.limited &&
          st != PermissionStatus.provisional) {
        return CallPermissionResult.denied;
      }
    }
    return CallPermissionResult.granted;
  } catch (e) {
    dlog('[CALL-PERM] ensureCallPermissions error: $e');
    // Gagal menanyakan izin (platform tak mendukung dsb) → jangan halangi
    // panggilan; biarkan `getUserMedia` jalur normal yang memutuskan.
    return CallPermissionResult.granted;
  }
}

/// Pesan untuk kegagalan setup media — dipakai CallScreen & overlay supaya
/// user tahu penyebabnya (izin vs kamera dipakai app lain), bukan "gagal
/// terhubung" generik untuk semua kasus.
String callMediaErrorMessage(S s, CallMediaError? err) {
  switch (err) {
    case CallMediaError.permission:
      return s.errCallPermission;
    case CallMediaError.inUse:
      return s.errCallMediaInUse;
    case CallMediaError.notFound:
      return s.errCallMediaNotFound;
    default:
      return s.msgCallError;
  }
}
