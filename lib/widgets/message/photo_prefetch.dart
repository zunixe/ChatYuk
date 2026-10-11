import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/cache/message_cache.dart';
import '../../core/cache/photo_cache.dart';
import '../../core/media/chat_photo_helper.dart';
import '../../models/message_model.dart';
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
      final photos = msgs
          .where((m) =>
              (m.type == 'image' || m.type == 'view_once') &&
              m.imageData.isNotEmpty)
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      var n = 0;
      for (final m in photos) {
        if (n >= maxPerChat) break;
        final data = m.imageData;
        final key = data.hashCode;
        if (decodedImageCache.containsKey(key)) continue; // sudah ter-decode.
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
        putDecodedCache(key, DecodedImage(bytes, dims.width, dims.height));
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
