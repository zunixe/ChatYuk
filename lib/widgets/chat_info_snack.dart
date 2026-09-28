import 'package:flutter/material.dart';

/// Pill info ala WhatsApp — melayang DI ATAS composer, bukan di dasar layar.
///
/// Masalah yang diperbaiki: `SnackBar(content: Text(...))` polos memakai
/// posisi default di dasar layar sehingga menutupi kolom ketik pesan +
/// tombol send selama ~4 detik. Di private chat lebih parah karena
/// `resizeToAvoidBottomInset: false` (keyboard diatur manual).
///
/// Pakai helper ini untuk SEMUA info transien di dalam chat
/// (copied, forwarded, starred, hapus, edit, kirim gagal, voice, foto).
/// Layar non-chat (settings/admin/form) tetap pakai SnackBar biasa.
SnackBar buildChatSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration duration = const Duration(milliseconds: 2500),
  Color? backgroundColor,
}) {
  final kb = MediaQuery.viewInsetsOf(context).bottom;
  return SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
    margin: EdgeInsets.only(left: 16, right: 16, bottom: kb + 76),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    duration: duration,
    action: action,
    backgroundColor: backgroundColor,
  );
}

/// Tampilkan pill info chat — buang snackbar sebelumnya dulu supaya
/// info cepat (copy → forward) tidak antre menumpuk.
void showChatSnack(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration duration = const Duration(milliseconds: 2500),
  Color? backgroundColor,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      buildChatSnackBar(
        context,
        message,
        action: action,
        duration: duration,
        backgroundColor: backgroundColor,
      ),
    );
}

/// Varian untuk pemanggil yang sudah memegang `ScaffoldMessengerState`
/// (mis. di dalam `catch` setelah `await`).
void showChatSnackVia(
  ScaffoldMessengerState messenger,
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration duration = const Duration(milliseconds: 2500),
  Color? backgroundColor,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      buildChatSnackBar(
        context,
        message,
        action: action,
        duration: duration,
        backgroundColor: backgroundColor,
      ),
    );
}
