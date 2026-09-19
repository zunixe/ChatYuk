import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Tombol kontrol panggilan (mic / kamera / speaker / end) — gaya sama
/// dengan kontrol broadcast grup: lingkaran filled-tonal + ikon rounded.
///
/// Dipakai `ChatCallOverlay` (video call dalam chat) & `CallScreen` supaya
/// bentuk tombol panggilan konsisten antar layar.
class CallControlButton extends StatelessWidget {
  final IconData icon;
  /// true = state "mati" (mic off / kamera off) → warna danger.
  final bool off;
  final VoidCallback onTap;
  /// true = tombol akhiri panggilan (selalu danger).
  final bool danger;
  final double size;

  const CallControlButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.off = false,
    this.danger = false,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    // Tombol "danger" (end call) = bulatan penuh warna danger + ikon PUTIH.
    // Tombol off (mic/kamera/speaker mati) = bulatan tint danger + ikon danger.
    // Dulu danger & off sama-sama pakai fg danger → ikon end call menyatu
    // dengan latarnya (tak terlihat).
    final bg = danger
        ? AppTheme.danger
        : off
        ? AppTheme.danger.withValues(alpha: 0.22)
        : Colors.white.withValues(alpha: 0.18);
    final fg = danger ? Colors.white : (off ? AppTheme.danger : Colors.white);
    return Material(
      color: bg,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: fg, size: size * 0.5),
        ),
      ),
    );
  }
}
