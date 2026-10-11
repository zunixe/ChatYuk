import 'package:flutter/material.dart';

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
const Duration kChatRouteDuration = Duration(milliseconds: 150);
const Duration kChatRouteReverseDuration = Duration(milliseconds: 120);

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
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}
