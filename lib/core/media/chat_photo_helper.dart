import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'forensic_watermark.dart';

/// Modul BERSAMA pemrosesan foto chat (private ↔ room).
///
/// Fungsi top-level (bukan method) karena dipanggil lewat `compute()` —
/// wajib bisa dijalankan di isolate terpisah.
///
/// Dulu dua salinan identik hidup di `private_chat_screen` dan
/// `room_chat_screen` (`_processViewOnceImage`/`_passthroughImage` vs
/// `_roomViewOnceImage`/`_roomPassthroughImage`). Sekarang satu sumber.

/// View-once: sematkan watermark forensik (seed = uid/room id pengirim).
String? processViewOnceImage((Uint8List, String) args) {
  final (bytes, seed) = args;
  return ForensicWatermark.embedToBase64(bytes, seed);
}

/// Foto biasa: resize maks 1200px + JPEG q82, tanpa watermark.
///
/// Kamera mengirim foto besar (10-20MB); tanpa resize penerima gagal decode.
String? processChatPhoto(Uint8List bytes) {
  // image 4.x MELEMPAR untuk bytes korup/pendek — jangan biarkan crash.
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final w = decoded.width;
  final h = decoded.height;
  final img.Image resized = (w <= 1200 && h <= 1200)
      ? decoded
      : img.copyResize(
          decoded,
          width: w > h ? 1200 : null,
          height: h >= w ? 1200 : null,
        );
  return base64Encode(img.encodeJpg(resized, quality: 82));
}

/// Resize proporsional (sisi terpanjang 800) + JPEG q75, return base64.
/// Dipakai foto chat biasa (jalur `chat_photo_send_mixin`). Harus top-level
/// untuk `compute()` isolate. Pindah dari widgets/chat_ui_shared.dart
/// (Fase 11): helper murni wajib di core/, bukan di folder widgets.
String? processChatImage(Uint8List bytes) {
  // image 4.x MELEMPAR untuk bytes korup/pendek — jangan biarkan crash.
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final w = decoded.width;
  final h = decoded.height;
  final img.Image resized = (w <= 800 && h <= 800)
      ? decoded
      : img.copyResize(
          decoded,
          width: w > h ? 800 : null,
          height: h >= w ? 800 : null,
        );
  return base64Encode(img.encodeJpg(resized, quality: 75));
}
