import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'chat_photo_helper.dart' as dartimg;

/// Pipeline gambar NATIVE (Kotlin `BitmapFactory`) via MethodChannel
/// `com.chatyuk.chatyuk/image`, dengan **fallback transparan** ke Dart
/// (`compute` + `package:image`) bila channel tak tersedia (unit test, desktop,
/// atau kegagalan native).
///
/// Alasan: engine Flutter menahan banyak base64/bytes di heap Dart → proses
/// membengkak & ter-swap. Decode/encode di native + LRU native membuat data
/// besar tidak hidup di heap Dart (pola seperti WA).
class NativeImage {
  NativeImage._();

  static const MethodChannel _ch = MethodChannel('com.chatyuk.chatyuk/image');

  /// True bila channel native tersedia (di-cache setelah probe pertama).
  static bool? _available;

  @visibleForTesting
  static void resetAvailabilityForTest() => _available = null;

  /// Probe channel (sekali). Di unit test tanpa binding native → false.
  static Future<bool> isAvailable() async {
    if (_available != null) return _available!;
    if (kIsWeb) {
      _available = false;
      return false;
    }
    try {
      // `aspectRatio` dengan payload kosong → native balas null cepat.
      await _ch.invokeMethod<dynamic>('aspectRatio', {'base64': ''});
      _available = true;
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  /// Dimensi dari HEADER saja (tanpa decode penuh). Fallback: parseImageDimensions Dart.
  static Future<({int width, int height})?> aspectRatio(String base64) async {
    if (base64.isEmpty) return null;
    if (await isAvailable()) {
      try {
        final r = await _ch.invokeMethod<dynamic>('aspectRatio', {'base64': base64});
        if (r is Map && r['w'] is int && r['h'] is int) {
          return (width: r['w'] as int, height: r['h'] as int);
        }
        return null;
      } catch (_) {
        // jatuh ke fallback
      }
    }
    final bytes = _tryB64(base64);
    if (bytes == null) return null;
    return dartimg.parseImageDimensions(bytes);
  }

  /// Decode + downscale ke sisi terpanjang [maxPx] + JPEG [quality] → bytes.
  /// Fallback: decode Dart di isolate (thumbnail).
  static Future<Uint8List?> decodeThumb(
    String base64, {
    int maxPx = 256,
    int quality = 80,
  }) async {
    if (base64.isEmpty) return null;
    if (await isAvailable()) {
      try {
        final r = await _ch.invokeMethod<Uint8List>('decodeThumb', {
          'base64': base64,
          'maxPx': maxPx,
          'quality': quality,
        });
        if (r != null && r.isNotEmpty) return r;
        return null;
      } catch (_) {}
    }
    final bytes = _tryB64(base64);
    if (bytes == null) return null;
    return compute(dartimg.dartDecodeThumbBytes, (bytes, maxPx, quality));
  }

  /// Decode base64 → bytes gambar utuh (untuk `Image.memory`).
  /// Fallback: `base64Decode` di isolate. (Input kosong dibiarkan lewat jalur
  /// fallback `compute` agar paritas dengan pemanggil lama.)
  static Future<Uint8List?> decodeBytes(String base64) async {
    if (await isAvailable()) {
      try {
        final r = await _ch.invokeMethod<Uint8List>('decodeBytes', {'base64': base64});
        if (r != null && r.isNotEmpty) return r;
      } catch (_) {}
    }
    return compute(_b64ToBytes, base64);
  }

  /// Decode base64 → (bytes, w, h) dalam SATU round-trip (bubble chat).
  /// Fallback: `compute(decodeImageB64)`.
  static Future<({Uint8List bytes, int width, int height})?> decodeWithDims(
    String base64,
  ) async {
    if (base64.isEmpty) return null;
    if (await isAvailable()) {
      try {
        final r = await _ch.invokeMethod<dynamic>('decodeWithDims', {'base64': base64});
        if (r is Map && r['bytes'] is Uint8List) {
          return (
            bytes: r['bytes'] as Uint8List,
            width: (r['w'] as int?) ?? 0,
            height: (r['h'] as int?) ?? 0,
          );
        }
        return null;
      } catch (_) {}
    }
    final bytes = _tryB64(base64);
    if (bytes == null) return null;
    final dims = dartimg.parseImageDimensions(bytes);
    return (bytes: bytes, width: dims?.width ?? 0, height: dims?.height ?? 0);
  }

  /// Avatar: decode + downscale ke [maxPx] → JPEG bytes.
  static Future<Uint8List?> decodeAvatar(
    String base64, {
    int maxPx = 300,
  }) async {
    if (base64.isEmpty) return null;
    if (await isAvailable()) {
      try {
        final r = await _ch.invokeMethod<Uint8List>('decodeAvatar', {
          'base64': base64,
          'maxPx': maxPx,
        });
        if (r != null && r.isNotEmpty) return r;
        return null;
      } catch (_) {}
    }
    final bytes = _tryB64(base64);
    if (bytes == null) return null;
    return compute(dartimg.dartDecodeThumbBytes, (bytes, maxPx, 85));
  }

  /// Proses foto KIRIM: resize sisi terpanjang [maxPx] + JPEG [quality] → base64.
  /// Fallback: `package:image` di isolate.
  static Future<String?> processJpeg(
    Uint8List src, {
    int maxPx = 800,
    int quality = 75,
  }) async {
    if (src.isEmpty) return null;
    if (await isAvailable()) {
      try {
        final r = await _ch.invokeMethod<String>('processJpeg', {
          'bytes': src,
          'maxPx': maxPx,
          'quality': quality,
        });
        if (r != null && r.isNotEmpty) return r;
        return null;
      } catch (_) {}
    }
    final p = (maxPx, quality);
    if (p == (800, 75)) return compute(dartimg.processChatImage, src);
    if (p == (1200, 82)) return compute(dartimg.processChatPhoto, src);
    if (p == (1920, 90)) return compute(dartimg.processChatImageHd, src);
    return compute(dartimg.dartProcessJpegB64, (src, maxPx, quality));
  }

  static Uint8List? _tryB64(String b64) {
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }
}

Uint8List? _b64ToBytes(String b64) {
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}
