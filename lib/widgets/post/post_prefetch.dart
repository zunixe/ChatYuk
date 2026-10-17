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

  /// Maks foto per post yang di-prefetch (feed = foto utama, sisa = tile).
  static const int maxPhotosPerPost = 4;

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

  /// Prefetch thumb [posts] teratas (maks [maxPosts] post). Foto PERTAMA
  /// (tampil di feed) = varian [PostImageVariant.feed]; foto carousel lain =
  /// varian [PostImageVariant.tile] (kecil) — bounded per post.
  /// Dari CACHE DISK dulu (instan) → baru download bila belum ada.
  static void warmPosts(List<Map<String, dynamic>> posts) {
    final store = PostPhotoCache.instance;
    var n = 0;
    for (final p in posts) {
      if (n >= maxPosts) break;
      final paths = pathsOf(p);
      if (paths.isEmpty) continue;
      n++;
      // Foto utama feed.
      _warmOne(store, paths.first, PostImageVariant.feed);
      // Sisa foto (carousel) → tile, bounded.
      for (var i = 1; i < paths.length && i < maxPhotosPerPost; i++) {
        _warmOne(store, paths[i], PostImageVariant.tile);
      }
    }
  }

  /// Hangatkan satu (path, varian) — dedupe via _done/_inflight.
  static void _warmOne(
    PostPhotoCache store,
    String path,
    PostImageVariant variant,
  ) {
    final key = '${variant.tag}:$path';
    if (_done.contains(key) || _inflight.contains(key)) return;
    if (store.thumbSync(path, variant: variant) != null) {
      _markDone(key);
      return;
    }
    _inflight.add(key);
    unawaited(
      store.thumb(path, variant: variant).then((b) {
        if (b != null) _markDone(key);
      }).whenComplete(() => _inflight.remove(key)),
    );
  }

  /// Prefetch thumb [ahead] post DI DEPAN index [from] — dipakai `itemBuilder`
  /// saat kartu dibangun. Berbeda dari prefetch berbasis posisi-scroll, ini
  /// mengekor index yang benar-benar dibangun sehingga TETAP unggul saat
  /// scroll cepat (posisi melompat). [ahead] kecil (default 4) supaya tidak
  /// membuang bandwidth untuk post jauh.
  static void warmAheadFrom(
    List<Map<String, dynamic>> posts,
    int from, {
    int ahead = 8,
  }) {
    if (posts.isEmpty) return;
    final start = from + 1;
    final end = (start + ahead).clamp(0, posts.length);
    if (start >= end) return;
    warmPosts(posts.sublist(start, end));
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
