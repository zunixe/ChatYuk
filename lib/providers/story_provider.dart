import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils.dart';

import '../core/cache/media_disk_cache.dart';
import '../models/story_model.dart';
import '../services/rt_resilient.dart';
import '../services/storage_photo_service.dart';
import '../services/story_service.dart';

/// State story: tray (daftar author aktif), slide per author yang sedang
/// dibuka, dan sinkron realtime (slide baru / dilihat) supaya ring di tray
/// update tanpa refresh manual.
class StoryProvider extends ChangeNotifier {
  final StoryService _service;
  bool _disposed = false;

  List<StoryTrayItem> _tray = [];
  bool _loading = false;
  String? _error;

  /// Slide per author — di-cache supaya buka penonton berikutnya instan.
  final Map<String, List<StorySlide>> _slidesByAuthor = {};

  /// Thumbnail tray per `thumbPath` — RAM cache (bytes). Tanpa ini setiap
  /// tile baru (rebuild/refresh/cold start) mengulang baca disk → thumbnail
  /// "keload ulang" padahal sudah ada. Sama seperti pola avatar (RAM→disk→net).
  final Map<String, Uint8List> _thumbByPath = {};

  /// Job thumbnail in-flight per path — caller kedua menunggu job yang sama
  /// (bukan mulai unduh ganda).
  final Map<String, Future<Uint8List?>> _thumbJobs = {};
  static const int _maxThumbs = 80;

  StreamSubscription? _storiesSub;
  StreamSubscription? _viewsSub;
  Timer? _refreshDebounce;

  List<StoryTrayItem> get tray => _tray;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasOwnStory => _tray.any((t) => t.own && t.slideCount > 0);

  /// Item tray milik sendiri (null kalau belum pernah bikin story).
  StoryTrayItem? get ownItem {
    for (final t in _tray) {
      if (t.own) return t;
    }
    return null;
  }

  StoryProvider({StoryService? service})
    : _service = service ?? StoryService() {
    // Resilient: tanpa onError, error channel MEMBUNUH subscription
    // (tray story freeze sampai restart).
    _storiesSub = listenResilient<String>(
      () => _service.watchStories(),
      (_) => _scheduleRefresh(),
      isDisposed: () => _disposed,
      onError: (e) => dlog('[StoryProvider] stories stream error: $e'),
    );
    _viewsSub = listenResilient<String>(
      () => _service.watchStoryViews(),
      (_) => _scheduleRefresh(),
      isDisposed: () => _disposed,
      onError: (e) => dlog('[StoryProvider] views stream error: $e'),
    );
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 500), () {
      refresh(silent: true);
    });
  }

  /// Muat tray. [silent] = tanpa state loading (dipakai realtime debounce).
  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      if (!_disposed) notifyListeners();
    }
    try {
      _tray = await _service.fetchTray();
      _error = null;
      // Prewarm thumbnail sinkron dari disk (bila prewarm disk sudah siap)
      // supaya tile pertama langsung terisi — tidak "hilang dulu" lalu tampil.
      warmTrayThumbs();
    } catch (e) {
      dlog('[StoryProvider] refresh error: $e');
      _error = e.toString();
    }
    _loading = false;
    if (!_disposed) notifyListeners();
  }

  /// Slide author — dari cache kalau ada, else fetch.
  Future<List<StorySlide>> slidesFor(String authorId) async {
    final cached = _slidesByAuthor[authorId];
    if (cached != null && cached.isNotEmpty) return cached;
    final slides = await _service.fetchSlides(authorId);
    if (slides.isNotEmpty) _slidesByAuthor[authorId] = slides;
    return slides;
  }

  /// Thumbnail tray untuk [thumbPath] — RAM → disk (SINKRON, anti-blink) →
  /// network + tulis disk. Sumber kebenaran lokal sama seperti avatar:
  /// begitu pernah dimuat, tampil instan di rebuild/cold start berikutnya
  /// (tidak "keload ulang").
  ///
  /// [sync] = true mengembalikan HANYA hasil dari RAM/disk yang sudah siap
  /// (tanpa menunggu network) — dipakai tile agar frame pertama langsung
  /// terisi kalau cache ada. Bila null, pemanggil boleh await versi async.
  Uint8List? thumbCached(String thumbPath) {
    if (thumbPath.isEmpty) return null;
    final ram = _thumbByPath[thumbPath];
    if (ram != null) return ram;
    // Prewarm belum siap → jangan vonis miss (bisa fetch network sia-sia).
    if (!MediaDiskCache.instance.isReady) return null;
    final disk = MediaDiskCache.instance.readSync(_thumbKey(thumbPath));
    if (disk != null && disk.isNotEmpty) {
      _rememberThumb(thumbPath, disk);
      return disk;
    }
    return null;
  }

  /// Isi RAM cache thumbnail dari disk SECARA SINKRON bila memungkinkan.
  ///
  /// Pola ini yang menyamakan story dengan avatar: hasil disk ditulis ke RAM
  /// provider (bukan hanya disimpan di State widget). Tanpa ini, tiap tile
  /// baru (rebuild / ganti tab / scroll) kehilangan `_thumb` dan harus
  /// menunggu `waitReady()` → muncul efek "hilang dulu baru tampil".
  ///
  /// Return true bila RAM cache sudah terisi (siap dipakai paint pertama).
  bool warmThumb(String thumbPath) {
    if (thumbPath.isEmpty) return false;
    if (_thumbByPath.containsKey(thumbPath)) return true;
    if (!MediaDiskCache.instance.isReady) return false;
    final disk = MediaDiskCache.instance.readSync(_thumbKey(thumbPath));
    if (disk == null || disk.isEmpty) return false;
    _rememberThumb(thumbPath, disk);
    return true;
  }

  /// Prewarm semua thumbnail tray secara sinkron — dipanggil setelah tray
  /// dimuat supaya saat tile dibangun, cache RAM sudah terisi dan thumbnail
  /// tampil di frame pertama (tidak "hilang dulu").
  void warmTrayThumbs() {
    if (!MediaDiskCache.instance.isReady) return;
    for (final item in _tray) {
      final p = item.thumbPath;
      if (p.isEmpty) continue;
      warmThumb(p);
    }
  }

  /// Versi async: tunggu prewarm, cek RAM/disk, lalu (bila perlu) unduh +
  /// simpan disk. Unduhan digabung per-path (tidak ganda).
  Future<Uint8List?> thumbFor(String thumbPath) async {
    if (thumbPath.isEmpty) return null;
    final ram = _thumbByPath[thumbPath];
    if (ram != null) return ram;
    final job = _thumbJobs[thumbPath];
    if (job != null) return job;
    final future = _loadThumbNetwork(thumbPath);
    _thumbJobs[thumbPath] = future;
    try {
      return await future;
    } finally {
      _thumbJobs.remove(thumbPath);
    }
  }

  Future<Uint8List?> _loadThumbNetwork(String thumbPath) async {
    // Disk dulu (jangan salah vonis miss saat cold start).
    try {
      await MediaDiskCache.instance.waitReady();
      final disk = MediaDiskCache.instance.readSync(_thumbKey(thumbPath));
      if (disk != null && disk.isNotEmpty) {
        _rememberThumb(thumbPath, disk);
        return disk;
      }
    } catch (_) {}
    // Network: thumb server-side (proporsional, rasio = kartu preview viewer).
    try {
      final bytes = await StoragePhotoService.instance.downloadThumbBytes(
        thumbPath,
        width: 180,
        height: 316,
        resize: ResizeMode.cover,
      );
      if (bytes != null && bytes.isNotEmpty) {
        _rememberThumb(thumbPath, bytes);
        unawaited(MediaDiskCache.instance.write(_thumbKey(thumbPath), bytes));
        return bytes;
      }
    } catch (e) {
      dlog('[StoryProvider] thumb error: $e');
    }
    return null;
  }

  /// Kunci cache beda dari full image + mencakup dimensi (thumb lawas 160px
  /// tanpa resize aspeknya rusak — jangan dipakai lagi).
  String _thumbKey(String thumbPath) => '$thumbPath#thumb180x316';

  void _rememberThumb(String thumbPath, Uint8List bytes) {
    if (_thumbByPath.length >= _maxThumbs &&
        !_thumbByPath.containsKey(thumbPath)) {
      _thumbByPath.remove(_thumbByPath.keys.first);
    }
    _thumbByPath[thumbPath] = bytes;
  }

  /// Daftar penonton satu slide (pemilik slide only — server guard).
  Future<List<StoryViewer>> fetchViewers(String storyId) {
    return _service.fetchViewers(storyId);
  }

  /// Toggle like slide: optimistic dulu (hati langsung berubah), lalu
  /// koreksi dengan hasil server. Return status akhir (null = gagal →
  /// dikembalikan ke nilai semula).
  Future<bool?> toggleLike(String storyId, String authorId) async {
    final before = _findSlide(authorId, storyId);
    if (before == null) return null;
    final optimisticLiked = !before.liked;
    final optimisticCount = (before.likeCount + (optimisticLiked ? 1 : -1))
        .clamp(0, 1 << 30);
    _patchSlide(
      authorId,
      storyId,
      likeCount: optimisticCount,
      liked: optimisticLiked,
    );
    final res = await _service.toggleLike(storyId);
    if (res == null) {
      _patchSlide(
        authorId,
        storyId,
        likeCount: before.likeCount,
        liked: before.liked,
      );
      return null;
    }
    _patchSlide(authorId, storyId, likeCount: res.$2, liked: res.$1);
    return res.$1;
  }

  StorySlide? _findSlide(String authorId, String storyId) {
    for (final sl in _slidesByAuthor[authorId] ?? const <StorySlide>[]) {
      if (sl.id == storyId) return sl;
    }
    return null;
  }

  void _patchSlide(
    String authorId,
    String storyId, {
    required int likeCount,
    required bool liked,
  }) {
    final list = _slidesByAuthor[authorId];
    if (list == null) return;
    final i = list.indexWhere((s) => s.id == storyId);
    if (i < 0) return;
    list[i] = list[i].copyWith(likeCount: likeCount, liked: liked);
    if (!_disposed) notifyListeners();
  }

  /// Buang cache slide author (dipanggil viewer saat mau buka ulang /
  /// setelah ada perubahan realtime untuk author itu).
  void invalidateSlides(String authorId) {
    _slidesByAuthor.remove(authorId);
  }

  /// Optimistic: slide baru dibuat → langsung tampil di tray milik sendiri
  /// tanpa nunggu realtime round-trip.
  Future<bool> publish({
    required String imagePath,
    String textOverlay = '',
    double textX = 0.5,
    double textY = 0.85,
    int textColor = 0,
    int textSize = 1,
    double textScale = 1.0,
    bool textBg = false,
    String visibility = 'followers',
    required String myUid,
    required String myNickname,
    required String myAvatar,
  }) async {
    final id = await _service.createStory(
      imagePath: imagePath,
      textOverlay: textOverlay,
      textX: textX,
      textY: textY,
      textColor: textColor,
      textSize: textSize,
      textScale: textScale,
      textBg: textBg,
      visibility: visibility,
    );
    if (id.isEmpty) return false;
    // Optimistic tray update.
    final idx = _tray.indexWhere((t) => t.own);
    if (idx >= 0) {
      final old = _tray[idx];
      _tray[idx] = StoryTrayItem(
        authorId: old.authorId,
        authorName: myNickname,
        avatar: old.avatar,
        isRegistered: old.isRegistered,
        slideCount: old.slideCount + 1,
        thumbPath: imagePath,
        hasUnseen: old.hasUnseen,
        own: true,
      );
    } else {
      _tray.insert(
        0,
        StoryTrayItem(
          authorId: myUid,
          authorName: myNickname,
          avatar: myAvatar,
          isRegistered: true,
          slideCount: 1,
          thumbPath: imagePath,
          hasUnseen: false,
          own: true,
        ),
      );
    }
    _slidesByAuthor.remove(myUid);
    if (!_disposed) notifyListeners();
    // Refresh background supaya data server (urutan, unseen) sinkron.
    unawaited(refresh(silent: true));
    return true;
  }

  /// Hapus slide milik sendiri → refresh tray + cache.
  Future<bool> deleteSlide(String storyId, String authorId) async {
    final path = await _service.deleteStory(storyId);
    if (path.isEmpty) return false;
    _slidesByAuthor.remove(authorId);
    unawaited(refresh(silent: true));
    return true;
  }

  /// Tandai dilihat + update ring tray secara optimistic.
  Future<void> markSeen(String storyId, String authorId) async {
    _markSeenLocal(authorId);
    unawaited(_service.markSeen(storyId));
  }

  /// Tandai BANYAK slide sekaligus dalam SATU round-trip.
  /// Dipakai viewer: kumpulkan id yang benar-benar ditonton, kirim sekali
  /// saat keluar/ganti author — dulu 1 RPC per slide.
  Future<void> markSeenBulk(List<String> storyIds, String authorId) async {
    if (storyIds.isEmpty) return;
    _markSeenLocal(authorId);
    await _service.markSeenBulk(storyIds);
  }

  /// Update ring tray (hasUnseen=false) untuk satu author — sinkron, tanpa IO.
  void _markSeenLocal(String authorId) {
    var changed = false;
    for (int i = 0; i < _tray.length; i++) {
      final t = _tray[i];
      if (t.authorId == authorId && t.hasUnseen) {
        _tray[i] = StoryTrayItem(
          authorId: t.authorId,
          authorName: t.authorName,
          avatar: t.avatar,
          isRegistered: t.isRegistered,
          slideCount: t.slideCount,
          thumbPath: t.thumbPath,
          hasUnseen: false,
          own: t.own,
        );
        changed = true;
      }
    }
    if (changed && !_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshDebounce?.cancel();
    _storiesSub?.cancel();
    _viewsSub?.cancel();
    super.dispose();
  }
}
