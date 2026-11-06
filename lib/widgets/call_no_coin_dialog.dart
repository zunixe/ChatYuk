import 'dart:async';

import 'package:flutter/material.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/nav_gate.dart';
import '../models/topup_event.dart';
import '../providers/riverpod/locale_provider.dart';

/// Dialog "koin habis" saat panggilan berjalan.
///
/// Dipakai `CallScreen` (private call) dan `RandomCallScreen` (match).
/// Panggilan DIJEDA (tidak diputus) sampai user memilih:
///   • Isi Koin → buka sheet top-up; bila pembelian dimulai, tunggu hasil
///     Google Play (maks 3 menit), lalu `onContinue` dipanggil.
///   • Akhiri   → `onEnd` dipanggil.
///
/// Return `true` bila user memilih isi koin, `false` bila mengakhiri.
Future<bool> showCallNoCoinDialog(
  BuildContext context, {
  required int perMinute,
  required VoidCallback onEnd,
  required Future<void> Function() onContinue,
  Stream<TopupEvent>? topupEvents,
  VoidCallback? onTopupStart,
}) async {
  final s = S(isId: AppLocale.isId);

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

  // Tahan auto-hangup selama user membeli.
  onTopupStart?.call();
  // Dengar event SEBELUM sheet dibuka — sheet tertutup begitu paket diketuk,
  // sedangkan hasil Google Play datang belakangan.
  final waiter = topupEvents == null ? null : _TopupWaiter(topupEvents);
  try {
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
    // Pembelian dimulai → tunggu hasil nyata (maks 3 menit) sebelum
    // melanjutkan billing. Sheet ditutup tanpa beli → langsung lanjut.
    if (waiter != null && waiter.started && context.mounted) {
      final kind = await _showTopupWaiting(context, s, waiter);
      if (kind != TopupEventKind.credited && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.callTopupFailed)),
        );
      }
    }
  } finally {
    waiter?.cancel();
  }
  await onContinue();
  return true;
}

/// Pengamat event top-up untuk satu sesi pembelian.
class _TopupWaiter {
  _TopupWaiter(Stream<TopupEvent> events) {
    _sub = events.listen((e) {
      if (e.kind == TopupEventKind.started) started = true;
      if (e.kind == TopupEventKind.credited ||
          e.kind == TopupEventKind.failed ||
          e.kind == TopupEventKind.canceled) {
        if (!_done.isCompleted) _done.complete(e.kind);
      }
    });
  }

  late final StreamSubscription<TopupEvent> _sub;
  final _done = Completer<TopupEventKind>();
  bool started = false;

  Future<TopupEventKind?> wait(Duration timeout) =>
      _done.future.timeout(timeout, onTimeout: () => TopupEventKind.failed);

  void cancel() => _sub.cancel();
}

Future<TopupEventKind?> _showTopupWaiting(
  BuildContext context,
  S s,
  _TopupWaiter waiter,
) {
  final result = waiter.wait(const Duration(minutes: 3));
  return showDialog<TopupEventKind?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      result.then((k) {
        if (ctx.mounted) Navigator.of(ctx).pop(k);
      });
      return AlertDialog(
        backgroundColor: AppTheme.bgCard,
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                s.callTopupWaiting,
                style: AppText.body.copyWith(color: AppTheme.textPrimary),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Dialog "batas call gratis harian habis" (female → male).
/// Berbeda dengan koin habis: TIDAK ada tombol isi koin — server tidak
/// akan pernah menagih female, jadi satu-satunya aksi = akhiri panggilan.
Future<void> showCallFreeLimitDialog(
  BuildContext context, {
  required int limitMin,
  required VoidCallback onEnd,
}) async {
  final s = S(isId: AppLocale.isId);

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
