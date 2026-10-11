part of '../admin_provider.dart';

/// Domain admin: kelola TIMELINE (tab Timeline) — daftar SEMUA post lintas
/// user (public/followers/subscribers, tanpa batas RLS) + ubah visibilitas
/// untuk moderasi. Semua RPC bergantung admin (server guard).
mixin AdminTimelineMx on AdminBase {
  List<Map<String, dynamic>> _adminPosts = const [];
  bool _postsLoading = false;
  bool _postsLoaded = false;
  String _postFilter = 'all';
  Future<void>? _postsInFlight;

  List<Map<String, dynamic>> get adminPosts => _adminPosts;
  bool get postsLoading => _postsLoading;
  bool get postsLoaded => _postsLoaded;
  String get postFilter => _postFilter;

  /// Muat/segarkan daftar post (dedupe in-flight). [force] abaikan cache.
  Future<void> fetchPosts({bool force = false}) async {
    if (_disposed) return;
    if (!force && _postsLoaded && _adminPosts.isNotEmpty) return;
    final running = _postsInFlight;
    if (running != null) return running;
    final fut = _fetchPostsInner();
    _postsInFlight = fut;
    try {
      await fut;
    } finally {
      _postsInFlight = null;
    }
  }

  Future<void> _fetchPostsInner() async {
    if (_disposed) return;
    if (_adminPosts.isEmpty) {
      _postsLoading = true;
      _notifyPosts();
    }
    try {
      final list = await _service.adminTimelineAll(filter: _postFilter);
      if (_disposed) return;
      _adminPosts = list;
      _postsLoaded = true;
    } catch (e) {
      dlog('[Admin] fetchPosts error: $e');
      // Pertahankan data lama bila ada (jangan kosongkan saat error).
    } finally {
      _postsLoading = false;
      _notifyPosts();
    }
  }

  /// Ganti filter visibilitas → refetch.
  Future<void> setPostFilter(String filter) async {
    if (filter == _postFilter) return;
    _postFilter = filter;
    _postsLoaded = false;
    _notifyPosts();
    await fetchPosts(force: true);
  }

  /// Atur visibilitas satu post → optimistik update lokal + RPC.
  Future<bool> setPostVisibility(String postId, String visibility) async {
    final ok = await _service.adminSetPostVisibility(postId, visibility);
    if (!ok) return false;
    _adminPosts = _adminPosts.map((p) {
      if ('${p['id']}' != postId) return p;
      final m = Map<String, dynamic>.from(p);
      m['visibility'] = visibility;
      return m;
    }).toList();
    _notifyPosts();
    return true;
  }
}
