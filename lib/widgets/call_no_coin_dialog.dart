import 'package:flutter/material.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/nav_gate.dart';

/// Dialog "koin habis" saat panggilan berjalan.
///
/// Dipakai `CallScreen` (private call) dan `RandomCallScreen` (match).
/// Panggilan DIJEDA (tidak diputus) sampai user memilih:
///   • Isi Koin → buka sheet top-up, lalu `onContinue` dipanggil.
///   • Akhiri   → `onEnd` dipanggil.
///
/// Return `true` bila user memilih isi koin, `false` bila mengakhiri.
Future<bool> showCallNoCoinDialog(
  BuildContext context, {
  required int perMinute,
  required VoidCallback onEnd,
  required Future<void> Function() onContinue,
}) async {
  final s = S(isId: Localizations.localeOf(context).languageCode == 'id');

  final topup = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.hourglass_empty_rounded,
              color: Colors.orange, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.callNoCoinTitle,
              style: AppText.title.copyWith(color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
      content: Text(
        s.callNoCoinBody(perMinute),
        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            s.callNoCoinEnd,
            style: AppText.bodySmall.copyWith(color: AppTheme.danger),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: Text(s.callNoCoinTopup),
        ),
      ],
    ),
  );

  if (topup != true) {
    onEnd();
    return false;
  }

  // Buka sheet top-up dan TUNGGU sampai tertutup — baru coba resume
  // billing. Dulu `onContinue` dipanggil langsung sebelum user sempat
  // beli → tick resume selalu gagal "saldo masih kurang".
  if (context.mounted) {
    final show = NavGate.topupSheet;
    if (show != null) {
      await show(context, s);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.yukcoinTopupSoon)),
      );
    }
  }
  await onContinue();
  return true;
}

/// Dialog "batas call gratis harian habis" (female → male).
/// Berbeda dengan koin habis: TIDAK ada tombol isi koin — server tidak
/// akan pernah menagih female, jadi satu-satunya aksi = akhiri panggilan.
Future<void> showCallFreeLimitDialog(
  BuildContext context, {
  required int limitMin,
  required VoidCallback onEnd,
}) async {
  final s = S(isId: Localizations.localeOf(context).languageCode == 'id');

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          const Icon(Icons.timelapse_rounded, color: Colors.orange, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.callFreeLimitTitle,
              style: AppText.title.copyWith(color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
      content: Text(
        s.callFreeLimitBody(limitMin),
        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.danger,
            foregroundColor: Colors.white,
          ),
          child: Text(s.callNoCoinEnd),
        ),
      ],
    ),
  );
  onEnd();
}
