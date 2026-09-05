import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/story_model.dart';
import '../services/story_service.dart';

/// State story: tray (daftar author aktif), slide per author yang sedang
/// dibuka, dan sinkron realtime (slide baru / dilihat) supaya ring di tray
/// update tanpa refresh manual.
class StoryProvider extends ChangeNotifier {
  final StoryService _service = StoryService();
  bool _disposed = false;

  List<StoryTrayItem> _tray = [];
  bool _loading = false;
  String? _error;

  /// Slide per author — di-cache supaya buka penonton berikutnya instan.
  final Map<String, List<StorySlide>> _slidesByAuthor = {};

  StreamSubscription? _storiesSub;
  StreamSubscription? _viewsSub;
  Timer? _refreshDebounce;

  List<StoryTrayItem> get tray => _tray;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasOwnStory =>
      _tray.any((t) => t.own && t.slideCount > 0);

  /// Item tray milik sendiri (null kalau belum pernah bikin story).
  StoryTrayItem? get ownItem {
    for (final t in _tray) {
      if (t.own) return t;
    }
    return null;
  }

  StoryProvider() {
    _storiesSub = _service.watchStories().listen((_) => _scheduleRefresh());
    _viewsSub = _service.watchStoryViews().listen((_) => _scheduleRefresh());
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
    } catch (e) {
      debugPrint('[StoryProvider] refresh error: $e');
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

  /// Daftar penonton satu slide (pemilik slide only — server guard).
  Future<List<StoryViewer>> fetchViewers(String storyId) {
    return _service.fetchViewers(storyId);
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
    String visibility = 'registered',
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
    unawaited(_service.markSeen(storyId));
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
