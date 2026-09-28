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

/// Dimensi cepat dari header bytes (JPEG SOF / PNG IHDR) — sinkron, tanpa
/// isolate, tanpa decode penuh. Dipakai placeholder bubble foto agar langsung
/// mencadangkan aspek yang benar dari frame pertama (anti "kotak dulu baru
/// loncat bentuk" / nge-blink saat kirim). Return null bila format tak
/// dikenal / bytes korup. Murni & testable.
({int width, int height})? parseImageDimensions(Uint8List bytes) {
  try {
    if (bytes.length < 4) return null;
    // PNG: signature 8 byte, lalu chunk IHDR (width/height BE di byte 16-23).
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes.length >= 24 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      final w =
          (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final h =
          (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      if (w > 0 && h > 0 && w <= 10000 && h <= 10000) {
        return (width: w, height: h);
      }
      return null;
    }
    // JPEG: SOI (FF D8) lalu pindai marker sampai ketemu SOF.
    if (bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    var i = 2;
    var guard = 0;
    while (i + 1 < bytes.length && guard++ < 200) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      while (i < bytes.length && bytes[i] == 0xFF) {
        i++;
      }
      if (i >= bytes.length) break;
      final marker = bytes[i++];
      if (marker == 0xD9) break; // EOI
      // Standalone tanpa panjang: TEM, RSTn, SOI.
      if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) continue;
      if (marker == 0xDA) break; // SOS: data scan, SOF pasti sebelumnya
      if (i + 1 >= bytes.length) break;
      final len = (bytes[i] << 8) | bytes[i + 1];
      if (len < 2) break;
      // SOF0-SOF15 kecuali DHT (C4), JPG (C8), DAC (CC), DNL (DC).
      final isSof = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC &&
          marker != 0xDC;
      if (isSof) {
        if (i + 7 >= bytes.length) break;
        final h = (bytes[i + 3] << 8) | bytes[i + 4];
        final w = (bytes[i + 5] << 8) | bytes[i + 6];
        if (w > 0 && h > 0 && w <= 10000 && h <= 10000) {
          return (width: w, height: h);
        }
        return null;
      }
      i += len;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Ukuran bubble foto (maks 200×280) sesuai rasio asli — dipakai gambar yang
/// sudah ter-decode MAUPUN placeholder loading supaya ukurannya sama persis
/// (tidak ada lompatan layout saat foto selesai dimuat). Murni & testable.
({double width, double height}) photoViewSize(int w, int h) {
  if (w <= 0 || h <= 0) return (width: 200.0, height: 200.0);
  var width = 200.0;
  var height = width * h / w;
  if (height > 280) {
    height = 280;
    width = height * w / h;
  }
  return (width: width, height: height);
}

/// Gate prefetch foto background (list pesan → chat dibuka): true bila pesan
/// terakhir dari LAWAN dan lebih baru dari yang sudah diproses. Event
/// non-pesan (centang baca, pin) membawa lastMessageAt yang sama → false.
/// Murni & testable.
bool shouldPrefetchChatPhoto({
  required String lastSenderId,
  required String myUid,
  required DateTime lastMessageAt,
  required DateTime? seenAt,
}) {
  if (lastSenderId.isEmpty || lastSenderId == myUid) return false;
  if (seenAt != null && !lastMessageAt.isAfter(seenAt)) return false;
  return true;
}
/// Varian HD (ala WhatsApp): sisi terpanjang 1920 + JPEG q90 (~0.8–2MB).
/// Dipakai bila user menyalakan toggle HD di preview. Harus top-level
/// untuk `compute()` isolate (pola sama dengan processChatImage).
String? processChatImageHd(Uint8List bytes) {
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
  final img.Image resized = (w <= 1920 && h <= 1920)
      ? decoded
      : img.copyResize(
          decoded,
          width: w > h ? 1920 : null,
          height: h >= w ? 1920 : null,
        );
  return base64Encode(img.encodeJpg(resized, quality: 90));
}
