import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/cache/message_cache.dart';
import '../../core/cache/photo_cache.dart';
import '../../core/media/chat_photo_helper.dart';
import '../../models/message_model.dart';
import '../video_prefetch.dart';
import 'image_decode_core.dart';

/// Pre-decode FOTO/THUMB chat ke [decodedImageCache] SEBELUM layar chat tampil.
///
/// Masalah (cold start): [MessageImage] cek `decodedImageCache[imageData.hashCode]`
/// — di cold start cache itu KOSONG → decode async (baca disk/decrypt +
/// `compute` isolate) memakan 2-4 frame → foto "ngeload dulu". Voice langsung
/// karena tak butuh decode; video sudah di-precache posternya.
///
/// Solusi (pola sama video): saat TAP kartu chat (di list/online), decode thumb
/// terbaru di latar SELAMA transisi 150ms → frame pertama chat langsung foto.
/// Fire-and-forget, bounded, tak melempar.
class PhotoPrefetch {
  PhotoPrefetch._();

  /// Maks foto di-precache per buka chat (bounded — hemat CPU & RAM).
  static const int maxPerChat = 6;

  /// Precache SEMUA media chat (poster video + thumb foto) untuk [chatKey]
  /// (`private_<chatId>` atau `room_<roomId>`). Dipanggil saat TAP sebelum push
  /// supaya frame pertama chat sudah terisi gambar (nol 'ngeload'). Bounded &
  /// tidak melempar; pemanggil boleh beri timeout.
  static Future<void> precacheAll(BuildContext context, String chatKey) async {
    try {
      await VideoPrefetch.precachePosters(context, chatKey);
    } catch (_) {}
    try {
      await PhotoPrefetch.precacheThumbs(context, chatKey);
    } catch (_) {}
  }

  /// Decode thumbnail `imageData` (path storage) yang sudah ada di PhotoCache
  /// disk → taruh di [decodedImageCache] memakai kunci `hashCode(imageData)`
  /// (KUNCI SAMA yang dibaca [MessageImage]) supaya frame pertama hit.
  static Future<void> precacheThumbs(
    BuildContext context,
    String chatKey,
  ) async {
    if (chatKey.isEmpty) return;
    try {
      final msgs =
          MessageCache.instance.peekMessages(chatKey) ?? const <MessageModel>[];
      if (msgs.isEmpty) return;
      // Ambil foto terbaru dulu (paling mungkin di viewport saat buka).
      // PENTING: JANGAN syaratkan `imageData.isNotEmpty` — di cache pesan,
      // base64 foto SENGAJA di-strip (hemat disk) sehingga `imageData` KOSONG
      // saat cold start. Thumb diambil by messageId dari PhotoCache.
      final photos = msgs
          .where((m) => m.type == 'image' || m.type == 'view_once')
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      var n = 0;
      for (final m in photos) {
        if (n >= maxPerChat) break;
        // Ambil thumb dari disk (bukan download) — hanya yang sudah ada.
        final thumbB64 = await PhotoCache.instance.loadThumb(chatKey, m.id);
        if (thumbB64 == null || thumbB64.isEmpty) continue;
        Uint8List bytes;
        try {
          bytes = base64Decode(thumbB64);
        } catch (_) {
          continue;
        }
        final dims = parseImageDimensions(bytes);
        if (dims == null) continue;
        final decoded = DecodedImage(bytes, dims.width, dims.height);
        // Daftarkan ke BEBERAPA kunci yang mungkin dipakai MessageImage:
        // - hashCode(imageData/base64) saat base64 ada
        // - hashCode(path) saat path storage ada
        // - khusus: kunci fallback by messageId agar selalu HIT saat cold
        //   start walau imageData kosong (base64 ter-strip dari cache).
        if (m.imageData.isNotEmpty) {
          putDecodedCache(m.imageData.hashCode, decoded);
        }
        putDecodedCache('thumb:${m.id}'.hashCode, decoded);
        n++;
      }
    } catch (err) {
      if (kDebugMode) debugPrint('[PhotoPrefetch] error: $err');
    }
  }

  /// Varian satu pesan (mis. foto baru masuk saat chat terbuka) — decode thumb
  /// ke cache agar bubble berikutnya tak "ngeload". Aman dipanggil berulang.
  static Future<void> precacheOne(
    String chatKey,
    String messageId,
    String imageData,
  ) async {
    if (chatKey.isEmpty || imageData.isEmpty) return;
    final key = imageData.hashCode;
    if (decodedImageCache.containsKey(key)) return;
    try {
      final thumbB64 = await PhotoCache.instance.loadThumb(chatKey, messageId);
      if (thumbB64 == null || thumbB64.isEmpty) return;
      final bytes = base64Decode(thumbB64);
      final dims = parseImageDimensions(bytes);
      if (dims == null) return;
      putDecodedCache(key, DecodedImage(bytes, dims.width, dims.height));
    } catch (_) {}
  }
}
