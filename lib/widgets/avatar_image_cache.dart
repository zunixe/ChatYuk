import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Cache AVATAR terpisah (lapis "small images") — ala Telegram
/// `ImageLoader.smallImagesMemCache`.
///
/// Masalah yang dipecahkan: `imageCache` global Flutter menyatukan SEMUA bitmap
/// (avatar 96px ≈ 36 KB vs foto timeline 1080px ≈ 4.4 MB). LRU evict berbasis
/// BYTE → **1 foto besar = ~124× avatar**, sehingga scroll Timeline (foto besar)
/// menyapu SEMUA avatar dari cache → buka list chat/decode ulang berulang.
///
/// Solusi: avatar punya store `ui.Image` SENDIRI (LRU by bytes, cap kecil),
/// lepas dari `imageCache` global. Render via `RawImage` (nol decode saat
/// render). 96px RGBA = 36 KB → cap 8 MB ≈ 220 avatar (muat >1 layar list).
///
/// Ownership jelas: hanya `user_avatar.dart` yang menulis/membaca store ini;
/// dibersihkan saat logout (`clear()`).
class AvatarImageCache {
  AvatarImageCache._();

  static final AvatarImageCache instance = AvatarImageCache._();

  /// Cap byte (8 MB ≈ 220 avatar 96px). Bounded — tidak tumbuh tanpa batas.
  static const int maxBytes = 8 * 1024 * 1024;

  final Map<String, ui.Image> _images = {};
  int _bytes = 0;
  final Map<String, Future<ui.Image?>> _jobs = {};

  @visibleForTesting
  int get bytes => _bytes;
  @visibleForTesting
  int get length => _images.length;

  /// `ui.Image` siap-render untuk [uid] bila ada (sinkron, tanpa decode).
  ui.Image? get(String uid) => _images[uid];

  /// Decode [bytes] → `ui.Image` (cap lebar [targetWidth]) lalu simpan.
  /// Penelepon paralel uid sama menunggu job yang sama. Null bila gagal.
  Future<ui.Image?> put(String uid, Uint8List bytes, {int targetWidth = 96}) {
    if (uid.isEmpty || bytes.isEmpty) return Future.value(null);
    final existing = _images[uid];
    if (existing != null) return Future.value(existing);
    final running = _jobs[uid];
    if (running != null) return running;
    final job = _decodeAndStore(uid, bytes, targetWidth);
    _jobs[uid] = job;
    return job.whenComplete(() {
      if (identical(_jobs[uid], job)) _jobs.remove(uid);
    });
  }

  Future<ui.Image?> _decodeAndStore(
    String uid,
    Uint8List bytes,
    int targetWidth,
  ) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
      );
      final frame = await codec.getNextFrame();
      final img = frame.image;
      _store(uid, img);
      return img;
    } catch (_) {
      return null;
    } finally {
      // Codec hanya alat decode; frame.image independen. Tanpa ini tiap
      // decode bocor 1 objek codec native.
      try {
        codec?.dispose();
      } catch (_) {}
    }
  }

  void _store(String uid, ui.Image img) {
    // Master lama untuk uid SAMA boleh di-dispose: setiap subscriber memegang
    // CLONE-nya sendiri (lihat loadImage), jadi dispose master tak mematikan
    // render yang sedang berjalan (refcount texture tetap >0 selama clone hidup).
    final old = _images.remove(uid);
    if (old != null) {
      _bytes -= _sizeOf(old);
      _safeDispose(old);
    }
    _images[uid] = img;
    _bytes += _sizeOf(img);
    // LRU penuh: evict + dispose master lama (subscriber-nya pegang clone).
    while (_bytes > maxBytes && _images.isNotEmpty) {
      final first = _images.keys.first;
      final ev = _images.remove(first)!;
      _bytes -= _sizeOf(ev);
      _safeDispose(ev);
    }
  }

  /// Tandai [uid] sebagai baru dipakai (LRU refresh) — pindah ke akhir.
  void touch(String uid) {
    final img = _images.remove(uid);
    if (img != null) _images[uid] = img;
  }

  static int _sizeOf(ui.Image img) => img.width * img.height * 4;

  static void _safeDispose(ui.Image img) {
    try {
      img.dispose();
    } catch (_) {}
  }

  /// Buang semua (logout / ganti akun). Aman: subscriber memegang clone.
  void clear() {
    for (final img in _images.values) {
      _safeDispose(img);
    }
    _images.clear();
    _bytes = 0;
  }

  /// Buang satu uid (foto profil diganti). Aman: subscriber pegang clone.
  void evict(String uid) {
    final img = _images.remove(uid);
    if (img != null) {
      _bytes -= _sizeOf(img);
      _safeDispose(img);
    }
  }
}

/// `ImageProvider` avatar yang memakai [AvatarImageCache] (bukan `imageCache`
/// global) — inilah "lapis kecil" yang terpisah dari foto besar.
///
/// `obtainKey` stabil per-uid (instance sama → widget tak re-subscribe),
/// `loadImage` membaca/mengisi store sendiri. Karena bitmap dikelola store
/// kita, LRU foto besar TIDAK bisa men-evict avatar.
@immutable
class AvatarMemoryImage extends ImageProvider<AvatarMemoryImage> {
  final String uid;
  final Uint8List bytes;
  final int width;
  const AvatarMemoryImage(this.uid, this.bytes, {this.width = 96});

  @override
  Future<AvatarMemoryImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<AvatarMemoryImage>(this);

  @override
  ImageStreamCompleter loadImage(
    AvatarMemoryImage key,
    ImageDecoderCallback decode,
  ) {
    final cached = AvatarImageCache.instance.get(key.uid);
    if (cached != null) {
      AvatarImageCache.instance.touch(key.uid);
      try {
        // WAJIB clone: master milik pool, handle ini milik subscriber.
        // Tanpa clone, dispose pool/evict/global-imageCache membunuh bitmap
        // yang masih dirender → "Cannot clone a disposed image" (2026-10-13).
        final handle = cached.clone();
        return OneFrameImageStreamCompleter(
          Future<ImageInfo>.value(ImageInfo(image: handle)),
        );
      } catch (_) {
        // Master mati balapan dengan evict → buang & decode ulang dari bytes.
        AvatarImageCache.instance.evict(key.uid);
      }
    }
    return OneFrameImageStreamCompleter(
      AvatarImageCache.instance
          .put(key.uid, key.bytes, targetWidth: key.width)
          .then((img) {
        if (img == null) {
          return Future<ImageInfo>.error(
            StateError('avatar decode fail'),
          );
        }
        try {
          return ImageInfo(image: img.clone());
        } catch (_) {
          AvatarImageCache.instance.evict(key.uid);
          return Future<ImageInfo>.error(
            StateError('avatar handle dead'),
          );
        }
      }),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AvatarMemoryImage &&
      other.uid == uid &&
      other.width == width &&
      identical(other.bytes, bytes);

  @override
  int get hashCode => Object.hash(uid, width, identityHashCode(bytes));

  @override
  String toString() => 'AvatarMemoryImage($uid, ${width}px)';
}
