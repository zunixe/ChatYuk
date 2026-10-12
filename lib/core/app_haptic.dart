import 'package:flutter/services.dart';

/// Getaran (haptic) terpusat — satu sumber agar konsisten di seluruh app,
/// menyerupai WhatsApp (getar RINGAN tiap tekan menu/tombol, bukan getar
/// berat).
///
/// Pakai [HapticFeedback] bawaan Flutter (tanpa dependency baru). Di Android
/// `lightImpact`/`selectionClick` memetakan ke getar pendek lembut; di
/// perangkat tanpa motor getar → no-op (aman).
///
/// JANGAN getar pada event non-tap (scroll, rebuild, async). Hanya di titik
/// interaksi user (onTap/onLongPress) supaya tidak mengganggu.
class AppHaptic {
  AppHaptic._();

  /// Getar tap MENU/tombol/list — ala WhatsApp (pendek, lembut).
  /// Dipakai bottom nav, tombol, kartu list, item menu.
  static void tap() => HapticFeedback.lightImpact();

  /// Getar seleksi/pilihan ringan (chips, tab, switch) — paling halus.
  static void select() => HapticFeedback.selectionClick();

  /// Getar aksi penting (kirim, hapus, konfirmasi) — sedikit lebih tegas.
  static void medium() => HapticFeedback.mediumImpact();
}
