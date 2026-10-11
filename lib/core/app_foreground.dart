import 'package:flutter/widgets.dart';

/// Status FOREGROUND app — dipakai gate timer/poll latar (hemat baterai).
///
/// Masalah yang dipecahkan (audit baterai 2026-10-11): beberapa `Timer.periodic`
/// tetap hidup saat app di-background/layar mati (heartbeat 240s, poll pesan &
/// list chat 30s, cek connectivity 20s) → wake + I/O sia-sia. `dumpsys
/// batterystats` menunjukkan ChatYuk pemakai baterai tertinggi dengan cached
/// CPU 3.17 mAh. Gating pada TAB saja (`visibleMainTab`) TIDAK cukup — tab
/// tetap "current" walau app di background.
///
/// Satu sumber kebenaran: di-set dari `WidgetsBindingObserver` lifecycle
/// (`_MainNav` di app.dart). Default `true` (aman: sebelum observer terpasang,
/// timer harus boleh jalan).
class AppForeground {
  AppForeground._();

  static final ValueNotifier<bool> isForeground = ValueNotifier<bool>(true);

  /// Dipanggil dari `didChangeAppLifecycleState`.
  static void set(AppLifecycleState state) {
    isForeground.value = state == AppLifecycleState.resumed;
  }

  /// True bila app sedang terlihat (resumed).
  static bool get now => isForeground.value;
}
