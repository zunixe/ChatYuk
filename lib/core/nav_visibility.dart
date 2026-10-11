import 'package:flutter/foundation.dart';

/// Tab utama yang sedang VISIBLE (di-set `_MainNav` di `app.dart`).
///
/// P1c (2026-10-11): tab utama ter-mount semua di `IndexedStack` → stream &
/// `Timer.periodic` tetap hidup walau tab non-aktif (`TickerMode` hanya
/// mematikan animasi). Gate kerja latar (poll list chat/presence) membaca ini
/// supaya tidak membuang I/O saat tab terkait tak terlihat.
///
/// Nilai: 0=Online, 1=Chat(list Pesan), 2=Timeline, 3=Profil.
final ValueNotifier<int> visibleMainTab = ValueNotifier<int>(0);
