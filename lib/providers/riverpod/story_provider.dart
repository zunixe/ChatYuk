import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/cache/media_disk_cache.dart';
import '../../core/cache/message_cache.dart';
import '../../models/story_model.dart';
import '../../services/rt_resilient.dart';
import '../../services/storage_photo_service.dart';
import '../../services/story_service.dart';
import '../../utils.dart';

/// State story (immutable — yang di-watch widget).
class StoryState {
  final List<StoryTrayItem> tray;
  final bool loading;
  final String? error;

  const StoryState({
    this.tray = const [],
    this.loading = false,
    this.error,
  });

  @override
  bool operator ==(Object other) =>
      other is StoryState &&
      other.loading == loading &&
      other.error == error &&
      listEquals(other.tray, tray);

  @override
  int get hashCode => Object.hash(loading, error, Object.hashAll(tray));

  bool get hasOwnStory => tray.any((t) => t.own && t.slideCount > 0);

  StoryTrayItem? get ownItem {
    for (final t in tray) {
      if (t.own) return t;
    }
    return null;
  }
}

/// State story: tray + sinkron realtime (Riverpod).
/// Migrasi dari ChangeNotifier → Notifier. Cache slide/thumbnail tetap
/// internal (tidak di-watch). Global (persist sepanjang sesi).
class StoryNotifier extends Notifier<StoryState> {
  final StoryService _service;

  StoryNotifier({StoryService? service})
      : _service = service ?? StoryService();

  List<StoryTrayItem> _tray = [];
  bool _loading = false;
  String? _error;
  DateTime? _lastTrayRefreshAt;

  static const String _kTrayKey = 'story_tray';

  final Map<String, List<StorySlide>> _slidesByAuthor = {};
  final Map<String, Uint8List> _thumbByPath = {};
  final Map<String, Future<Uint8List?>> _thumbJobs = {};
  static const int _maxThumbs = 80;

  StreamSubscription? _storiesSub;
  StreamSubscription? _viewsSub;
  Timer? _refreshDebounce;

  @override
  StoryState build() {
    ref.onDispose(_disposeAll);
    _storiesSub = listenResilient<String>(
      () => _service.watchStories(),
      (_) => _scheduleRefresh(),
      isDisposed: () => false,
      onError: (e) => dlog('[StoryProvider] stories stream error: $e'),
    );
    _viewsSub = listenResilient<String>(
      () => _service.watchStoryViews(),
      (_) => _scheduleRefresh(),
      isDisposed: () => false,
      onError: (e) => dlog('[StoryProvider] views stream error: $e'),
    );
    return const StoryState();
  }

  void _emit() {
    state = StoryState(
      tray: List.unmodifiable(_tray),
      loading: _loading,
      error: _error,
    );
  }

  // ── Getter kompat ──
  List<StoryTrayItem> get tray => _tray;
  bool get loading => _loading;
  String? get error => _error;

  /// Test hook: reset gate TTL refresh silent (45 dtk) agar refresh silent
  /// berikutnya benar-benar menembak `fetchTrayRaw` (dipakai unit test).
  void debugResetTrayTtl() => _lastTrayRefreshAt = null;

  bool get hasOwnStory => _tray.any((t) => t.own && t.slideCount > 0);
  StoryTrayItem? get ownItem {
    for (final t in _tray) {
      if (t.own) return t;
    }
    return null;
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 500), () {
      refresh(silent: true);
    });
  }

  Future<void> refresh({bool silent = false}) async {
    if (silent &&
        _lastTrayRefreshAt != null &&
        DateTime.now().difference(_lastTrayRefreshAt!).inSeconds < 45) {
      return;
    }
    if (!silent) {
      _loading = true;
      _emit();
    }
    if (_tray.isEmpty) {
      try {
        final cached = await MessageCache.instance.loadRawList(_kTrayKey);
        if (cached.isNotEmpty && _tray.isEmpty) {
          _tray = cached.map(StoryTrayItem.fromMap).toList();
          warmTrayThumbs();
          _emit();
        }
      } catch (_) {}
    }
    try {
      final fresh = await _service.fetchTrayRaw();
      if (fresh != null) {
        _tray = fresh.map(StoryTrayItem.fromMap).toList();
        _error = null;
        _lastTrayRefreshAt = DateTime.now();
        MessageCache.instance.saveRawList(
          _kTrayKey,
          fresh.map((e) => e).toList(),
        );
        warmTrayThumbs();
      }
    } catch (e) {
      dlog('[StoryProvider] refresh error: $e');
      _error = e.toString();
    }
    _loading = false;
    _emit();
  }

  Future<List<StorySlide>> slidesFor(String authorId,
      {int? expectedCount}) async {
    final cached = _slidesByAuthor[authorId];
    if (cached != null &&
        cached.isNotEmpty &&
        (expectedCount == null || cached.length == expectedCount)) {
      return cached;
    }
    final slides = await _service.fetchSlides(authorId);
    if (slides.isNotEmpty) {
      _slidesByAuthor[authorId] = slides;
      return slides;
    }
    return cached ?? slides;
  }

  Uint8List? thumbCached(String thumbPath) {
    if (thumbPath.isEmpty) return null;
    final ram = _thumbByPath[thumbPath];
    if (ram != null) return ram;
    if (!MediaDiskCache.instance.isReady) return null;
    final disk = MediaDiskCache.instance.readSync(_thumbKey(thumbPath));
    if (disk != null && disk.isNotEmpty) {
      _rememberThumb(thumbPath, disk);
      return disk;
    }
    return null;
  }

  bool warmThumb(String thumbPath) {
    if (thumbPath.isEmpty) return false;
    if (_thumbByPath.containsKey(thumbPath)) return true;
    if (!MediaDiskCache.instance.isReady) return false;
    final disk = MediaDiskCache.instance.readSync(_thumbKey(thumbPath));
    if (disk == null || disk.isEmpty) return false;
    _rememberThumb(thumbPath, disk);
    return true;
  }

  void warmTrayThumbs() {
    if (!MediaDiskCache.instance.isReady) return;
    for (final item in _tray) {
      final p = item.thumbPath;
      if (p.isEmpty) continue;
      warmThumb(p);
    }
  }

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
    try {
      await MediaDiskCache.instance.waitReady();
      final disk = MediaDiskCache.instance.readSync(_thumbKey(thumbPath));
      if (disk != null && disk.isNotEmpty) {
        _rememberThumb(thumbPath, disk);
        return disk;
      }
    } catch (_) {}
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

  String _thumbKey(String thumbPath) => '$thumbPath#thumb180x316';

  void _rememberThumb(String thumbPath, Uint8List bytes) {
    if (_thumbByPath.length >= _maxThumbs &&
        !_thumbByPath.containsKey(thumbPath)) {
      _thumbByPath.remove(_thumbByPath.keys.first);
    }
    _thumbByPath[thumbPath] = bytes;
  }

  Future<List<StoryViewer>?> fetchViewers(String storyId) {
    return _service.fetchViewers(storyId);
  }

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
    _emit();
  }

  void invalidateSlides(String authorId) {
    _slidesByAuthor.remove(authorId);
  }

  Future<Uint8List?> fetchSlideVideo(String videoPath) async {
    if (videoPath.isEmpty) return null;
    try {
      return await _service.downloadVideo(videoPath);
    } catch (e) {
      dlog('[Story] fetchSlideVideo error: $e');
      return null;
    }
  }

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
    String videoPath = '',
    int durationMs = 0,
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
      videoPath: videoPath,
      durationMs: durationMs,
    );
    if (id.isEmpty) return false;
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
    _emit();
    unawaited(refresh(silent: true));
    return true;
  }

  Future<bool> deleteSlide(String storyId, String authorId) async {
    final res = await _service.deleteStory(storyId);
    if (!res.ok) return false;
    final slides = _slidesByAuthor[authorId];
    if (slides != null) {
      for (var i = 0; i < slides.length; i++) {
        if (slides[i].id == storyId) {
          slides[i] = slides[i].copyWith(ownerOnly: true);
          break;
        }
      }
    }
    unawaited(refresh(silent: true));
    return true;
  }

  Future<void> markSeen(String storyId, String authorId) async {
    _markSeenLocal(authorId);
    unawaited(_service.markSeen(storyId));
  }

  Future<void> markSeenBulk(List<String> storyIds, String authorId) async {
    if (storyIds.isEmpty) return;
    _markSeenLocal(authorId);
    await _service.markSeenBulk(storyIds);
  }

  Future<bool> toggleStoryMute(String authorId, bool muted) async {
    final idx = _tray.indexWhere((t) => t.authorId == authorId);
    if (idx < 0) return muted;
    _tray[idx] = _tray[idx].copyWith(muted: muted);
    _tray.sort((a, b) {
      if (a.own != b.own) return a.own ? -1 : 1;
      if (a.muted != b.muted) return a.muted ? 1 : -1;
      if (a.hasUnseen != b.hasUnseen) return a.hasUnseen ? -1 : 1;
      return 0;
    });
    _emit();
    final ok = await _service.setStoryMuted(authorId, muted);
    if (!ok) {
      unawaited(refresh(silent: true));
    }
    return muted;
  }

  void _markSeenLocal(String authorId) {
    var changed = false;
    for (var i = 0; i < _tray.length; i++) {
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
    if (changed) _emit();
  }

  void _disposeAll() {
    _refreshDebounce?.cancel();
    _storiesSub?.cancel();
    _viewsSub?.cancel();
  }
}

final storyProvider =
    NotifierProvider<StoryNotifier, StoryState>(StoryNotifier.new);
