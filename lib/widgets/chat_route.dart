import 'package:flutter/material.dart';

import '../core/perf/perf_probe.dart';
import '../screens/private_chat_screen.dart';

/// Sumber TUNGGAL transisi & route halaman private chat.
///
/// Tujuan (keputusan 2026-10-11): SEMUA jalur masuk private chat wajib
/// memakai transisi yang SAMA — Slide + Fade 150/120ms `easeOutCubic` —
/// supaya konsisten & tidak "berat" (fade menutupi celah raster slide
/// full-screen di Skia-GL/Adreno). Halaman lain TETAP Slide murni dari
/// `AppSlidePageTransitionsBuilder` (theme.dart) — helper ini KHUSUS chat.
///
/// Sebelumnya transisi ini disalin manual di 2 tempat (chat list & Online)
/// sementara jalur lain (Nearby/CallHistory/UserInfo/RoomSheet) hanya Slide
/// murni → tidak konsisten. Sekarang semua lewat sini.
/// Durasi transisi buka chat — DISAMAKAN dengan WhatsApp (2026-10-18).
///
/// Diukur di HP (Xiaomi, 60fps): WhatsApp membuka chat dengan ±125-133 frame
/// (~2,1 detik animasi termasuk konten masuk). Sebelumnya ChatYuk hanya
/// 120ms — terasa "ngebut/lompat", bukan halus.
///
/// 250ms + `easeOutQuint` meniru rasa Android native: gerakan cepat di awal
/// lalu melambat lembut di akhir. Fade dihapus karena WhatsApp murni slide
/// (fade justru membuat tepi layar terlihat "dobel" saat slide).
const Duration kChatRouteDuration = Duration(milliseconds: 250);
const Duration kChatRouteReverseDuration = Duration(milliseconds: 220);

/// Transisi slide+fade [kChatRouteDuration] untuk layar BERAT selain chat
/// user (mis. monitor chat admin). Dipakai supaya semua jalur buka layar
/// sejenis punya durasi SAMA — `MaterialPageRoute` bawaan terukur lebih
/// lambat (183 ms vs 116 ms untuk layar yang sama isinya).
PageRoute<T> appSlideRoute<T>({
  required WidgetBuilder builder,
  String? name,
  Duration duration = kChatRouteDuration,
  bool fullscreenDialog = false,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: kChatRouteReverseDuration,
    settings: RouteSettings(name: name),
    fullscreenDialog: fullscreenDialog,
    pageBuilder: (context, _, __) => builder(context),
    transitionsBuilder: (_, animation, __, child) {
      // SLIDE MURNI ala WhatsApp: layar baru masuk dari kanan, layar lama
      // bergeser sedikit ke kiri (parallax) — tanpa fade.
      //
      // `easeOutQuint`: cepat di awal, sangat lembut di akhir. Ini kurva yang
      // dipakai animasi Material/Android native sehingga gerak terasa
      // "menempel" ke jari, bukan meluncur kaku.
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutQuint,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// Bangun route ke [PrivateChatScreen] dengan transisi Slide+Fade seragam.
PageRoute<void> chatRoute({
  required String chatId,
  required String otherName,
  required String otherUid,
  String otherGender = '',
  String otherCountry = '',
  int otherAge = 0,
  bool otherRegistered = false,
  bool initialOtherDeleted = false,
  String? routeName,
  /// Seed avatar header (base64 dari list) — anti-kedip inisial→foto.
  String otherAvatarB64 = '',
}) {
  // Ukur frame berat selama transisi (no-op bila PERF_PROBE off).
  PerfProbe.traceFrames(kChatRouteDuration + const Duration(milliseconds: 120));
  return PageRouteBuilder<void>(
    transitionDuration: kChatRouteDuration,
    reverseTransitionDuration: kChatRouteReverseDuration,
    settings: RouteSettings(name: routeName ?? 'private-chat:$chatId'),
    pageBuilder: (_, __, ___) => PrivateChatScreen(
      chatId: chatId,
      otherName: otherName,
      otherUid: otherUid,
      otherGender: otherGender,
      otherCountry: otherCountry,
      otherAge: otherAge,
      otherRegistered: otherRegistered,
      initialOtherDeleted: initialOtherDeleted,
      initialAvatarB64: otherAvatarB64,
    ),
    transitionsBuilder: (_, animation, __, child) {
      // SLIDE MURNI ala WhatsApp: layar baru masuk dari kanan, layar lama
      // bergeser sedikit ke kiri (parallax) — tanpa fade.
      //
      // `easeOutQuint`: cepat di awal, sangat lembut di akhir. Ini kurva yang
      // dipakai animasi Material/Android native sehingga gerak terasa
      // "menempel" ke jari, bukan meluncur kaku.
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutQuint,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}
