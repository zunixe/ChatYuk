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

// -- Fallback DART untuk NativeImage (dipakai bila channel native tak ada) --
// Top-level agar bisa dijalankan lewat `compute()`.

/// (bytes, maxPx, quality) ? JPEG bytes (thumb / avatar) atau null.
Uint8List? dartDecodeThumbBytes((Uint8List, int, int) args) {
  final (bytes, maxPx, quality) = args;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final w = decoded.width;
  final h = decoded.height;
  final img.Image resized = (w <= maxPx && h <= maxPx)
      ? decoded
      : img.copyResize(
          decoded,
          width: w > h ? maxPx : null,
          height: h >= w ? maxPx : null,
        );
  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}

/// (bytes, maxPx, quality) ? base64 JPEG (proses kirim generik) atau null.
String? dartProcessJpegB64((Uint8List, int, int) args) {
  final (bytes, maxPx, quality) = args;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final w = decoded.width;
  final h = decoded.height;
  final img.Image resized = (w <= maxPx && h <= maxPx)
      ? decoded
      : img.copyResize(
          decoded,
          width: w > h ? maxPx : null,
          height: h >= w ? maxPx : null,
        );
  return base64Encode(img.encodeJpg(resized, quality: quality));
}

/// Fallback DART thumbnail dari base64: resize lebar ke [maxW] + JPEG q[quality].
/// Paritas `decodeThumbB64` (width 256, quality 80). Top-level untuk compute().
String? dartThumbB64((String, int, int) args) {
  final (b64, maxW, quality) = args;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(base64Decode(b64));
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final w = decoded.width > maxW ? maxW : decoded.width;
  final h = (decoded.height * (w / decoded.width)).round();
  final thumb = img.copyResize(decoded, width: w, height: h,
      interpolation: img.Interpolation.linear);
  return base64Encode(img.encodeJpg(thumb, quality: quality));
}

/// Fallback DART raw RGBA → JPEG bytes. Paritas `encodeRawRgbaToJpg`.
/// Top-level untuk compute().
Uint8List? dartRawRgbaToJpg((Uint8List, int, int, int) args) {
  final (rgba, w, h, quality) = args;
  if (w <= 0 || h <= 0) return null;
  if (rgba.length < w * h * 4) return null;
  final image = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: quality));
}

/// Fallback DART downscale base64 ke lebar [targetWidth] + JPEG q[quality].
/// Paritas `_jpegDownscaled` (photo/post cache). Top-level untuk compute().
String? dartDownscaleB64((String, int, int) args) {
  final (b64, targetWidth, quality) = args;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(base64Decode(b64));
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final resized = (targetWidth > 0 && decoded.width > targetWidth)
      ? img.copyResize(decoded, width: targetWidth)
      : decoded;
  return base64Encode(img.encodeJpg(resized, quality: quality));
}

/// Fallback DART downscale bytes gambar ke lebar [targetWidth] + JPEG q[quality].
/// Paritas `_jpegDownscaled`. Top-level untuk compute().
Uint8List? dartDownscaleBytes((Uint8List, int, int) args) {
  final (bytes, targetWidth, quality) = args;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final resized = (targetWidth > 0 && decoded.width > targetWidth)
      ? img.copyResize(decoded, width: targetWidth)
      : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
}

/// Fallback DART rasio (w/h) BANYAK gambar sekaligus dari HEADER (PNG/JPEG).
/// Paritas `_aspectRatiosOfBytes` (satu list, bukan satu per foto).
List<double?> dartAspectRatios(List<Uint8List> list) {
  final out = <double?>[];
  for (final bytes in list) {
    final d = parseImageDimensions(bytes);
    out.add(d != null && d.width > 0 && d.height > 0 ? d.width / d.height : null);
  }
  return out;
}

/// Fallback DART thumbnail admin (dari bytes gambar): bila lebar > [maxW]
/// resize ke [maxW] (rasio dipertahankan) + JPEG [quality] → base64.
/// Paritas `genThumbB64`. Top-level untuk `compute()`.
String? dartAdminThumbB64((Uint8List, int, int) args) {
  final (bytes, maxW, quality) = args;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final w = decoded.width > maxW ? maxW : decoded.width;
  final h = (decoded.height * (w / decoded.width)).round();
  final thumb = img.copyResize(decoded, width: w, height: h);
  return base64Encode(img.encodeJpg(thumb, quality: quality));
}

/// Fallback DART foto galeri profil: full (lebar [fullW], q[fullQ]) + preview
/// kecil terblur. Paritas `_processPhotoWithPreview` di profile_screen.
/// Return `(fullB64, previewB64)` atau null. Top-level untuk `compute()`.
(String, String)? dartProcessGalleryPhoto((Uint8List, int, int, int, int, int) args) {
  final (bytes, fullW, fullQ, previewW, blur, previewQ) = args;
  var decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  // Orientasi EXIF — foto kamera jangan miring.
  decoded = img.bakeOrientation(decoded);
  final resized = img.copyResize(decoded, width: fullW);
  final full = base64Encode(img.encodeJpg(resized, quality: fullQ));
  var preview = img.copyResize(decoded, width: previewW);
  preview = img.gaussianBlur(preview, radius: blur);
  final previewB64 = base64Encode(img.encodeJpg(preview, quality: previewQ));
  return (full, previewB64);
}

/// Fallback DART avatar: resize ke [size]x[size] (crop-stretch, non-proporsional)
/// + JPEG q85 → base64. Top-level untuk `compute()`.
String? dartProcessSquareB64((Uint8List, int, int) args) {
  final (bytes, size, quality) = args;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final resized = img.copyResize(
    decoded,
    width: size,
    height: size,
    interpolation: img.Interpolation.cubic,
  );
  return base64Encode(img.encodeJpg(resized, quality: quality));
}

/// Fallback DART foto story: resize satu-sumbu ke [maxPx] (potret → tinggi,
/// lanskap → lebar) + JPEG q82 → base64. Top-level untuk `compute()`.
String? dartProcessStoryB64((Uint8List, int, int) args) {
  final (bytes, maxPx, quality) = args;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final isPortrait = decoded.height >= decoded.width;
  final resized = isPortrait
      ? img.copyResize(decoded, height: maxPx)
      : img.copyResize(decoded, width: maxPx);
  return base64Encode(img.encodeJpg(resized, quality: quality));
}

/// Fallback DART foto POST timeline: resize ke LEBAR tetap [maxW] (rasio
/// dipertahankan, paritas dgn `img.copyResize(width: 1080)`) + JPEG, sekaligus
/// kembalikan dimensi hasil. Top-level untuk `compute()`.
/// Return `(bytes, w, h)?`.
(Uint8List, int, int)? dartProcessPostDim((Uint8List, int, int) args) {
  final (bytes, maxW, quality) = args;
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  final resized = img.copyResize(decoded, width: maxW);
  return (
    Uint8List.fromList(img.encodeJpg(resized, quality: quality)),
    resized.width,
    resized.height,
  );
}