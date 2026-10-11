import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/cache/post_photo_cache.dart';

/// Prefetch thumbnail foto POST timeline ke [PostPhotoCache] (RAM+disk)
/// SEBELUM kartu masuk viewport — meniru perilaku chat foto/video & Instagram:
/// scroll/tampil berikutnya langsung gambar, bukan placeholder lalu menyusul.
///
/// Masalah: tiap [PostCard] baru memuat thumb-nya sendiri saat mount →
/// "item dulu, gambar menyusul". Prefetch mengambil N post TERATAS (paling
/// mungkin terlihat) di latar begitu daftar post tiba.
///
/// Fire-and-forget, bounded, tak melempar. Aman dipanggil berulang (dedupe
/// per path via `_inflight` + `_done`).
class PostPrefetch {
  PostPrefetch._();

  /// Maks post di-prefetch per batch (bounded — hemat data/CPU).
  static const int maxPosts = 8;

  static final Set<String> _done = {};
  static final Set<String> _inflight = {};
  static const int _doneCap = 500;

  /// Ambil path foto dari satu map post (pola sama [PostCard._imagePaths]).
  static List<String> pathsOf(Map<String, dynamic> post) {
    final arr = post['images'];
    if (arr is List && arr.isNotEmpty) {
      return arr
          .map((e) => '$e')
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    final single = post['imagePath'] as String? ?? '';
    return single.isNotEmpty ? [single] : const [];
  }

  /// Prefetch thumb [posts] teratas (maks [maxPosts] post, satu foto/post).
  /// Dari CACHE DISK dulu (instan) → baru download bila belum ada.
  static void warmPosts(List<Map<String, dynamic>> posts) {
    final store = PostPhotoCache.instance;
    var n = 0;
    for (final p in posts) {
      if (n >= maxPosts) break;
      final paths = pathsOf(p);
      if (paths.isEmpty) continue;
      // Ambil foto pertama (foto utama yang tampil di kartu feed).
      final path = paths.first;
      n++;
      if (_done.contains(path) || _inflight.contains(path)) continue;
      // Sudah ada di RAM/disk → tandai selesai, nol I/O.
      if (store.thumbSync(path) != null) {
        _markDone(path);
        continue;
      }
      _inflight.add(path);
      // `thumb()` baca disk dulu, lalu download bila perlu — fire-and-forget.
      unawaited(store.thumb(path).then((b) {
        if (b != null) _markDone(path);
      }).whenComplete(() => _inflight.remove(path)));
    }
  }

  static void _markDone(String path) {
    if (_done.length >= _doneCap) {
      _done.remove(_done.first);
    }
    _done.add(path);
  }

  /// Reset penanda (setelah refresh feed besar / logout).
  @visibleForTesting
  static void reset() {
    _done.clear();
    _inflight.clear();
  }
}
