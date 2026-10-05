part of '../admin_provider.dart';

/// Domain admin: kelola STORY (tab Story) — daftar semua slide, atur
/// visibilitas, hapus permanen. Semua RPC bergantung admin (server guard).
mixin AdminStoriesMx on AdminBase {
  List<Map<String, dynamic>> _stories = const [];
  bool _storiesLoading = false;
  bool _storiesLoaded = false;
  String _storyFilter = 'all';
  Future<void>? _storiesInFlight;

  List<Map<String, dynamic>> get stories => _stories;
  bool get storiesLoading => _storiesLoading;
  bool get storiesLoaded => _storiesLoaded;
  String get storyFilter => _storyFilter;

  /// Muat/segarkan daftar story (dedupe in-flight). [force] abaikan cache.
  Future<void> fetchStories({bool force = false}) async {
    if (_disposed) return;
    if (!force && _storiesLoaded && _stories.isNotEmpty) return;
    final running = _storiesInFlight;
    if (running != null) return running;
    final fut = _fetchStoriesInner();
    _storiesInFlight = fut;
    try {
      await fut;
    } finally {
      _storiesInFlight = null;
    }
  }

  Future<void> _fetchStoriesInner() async {
    if (_disposed) return;
    if (_stories.isEmpty) {
      _storiesLoading = true;
      _notifyStories();
    }
    try {
      final list = await _service.adminStoryAll(filter: _storyFilter);
      if (_disposed) return;
      _stories = list;
      _storiesLoaded = true;
    } catch (e) {
      dlog('[Admin] fetchStories error: $e');
      // Pertahankan data lama bila ada (jangan kosongkan saat error).
    } finally {
      _storiesLoading = false;
      _notifyStories();
    }
  }

  /// Ganti filter visibilitas → refetch.
  Future<void> setStoryFilter(String filter) async {
    if (filter == _storyFilter) return;
    _storyFilter = filter;
    _storiesLoaded = false;
    _notifyStories();
    await fetchStories(force: true);
  }

  /// Atur visibilitas satu slide → optimistik update lokal + RPC.
  Future<bool> setStoryVisibility(String storyId, String state) async {
    final ok = await _service.adminSetStoryVisibility(storyId, state);
    if (!ok) return false;
    _applyStoryState(storyId, state);
    return true;
  }

  /// Hapus PERMANEN satu slide → buang dari list + RPC.
  Future<bool> deleteStoryAdmin(String storyId) async {
    final res = await _service.adminStoryDelete(storyId);
    if (!res.ok) return false;
    _stories = _stories.where((s) => '${s['id']}' != storyId).toList();
    _notifyStories();
    return true;
  }

  /// Update lokal satu slide sesuai state baru (agar UI langsung berubah).
  void _applyStoryState(String storyId, String state) {
    _stories = _stories.map((s) {
      if ('${s['id']}' != storyId) return s;
      final m = Map<String, dynamic>.from(s);
      if (state == 'private') {
        m['owner_only'] = true;
      } else {
        m['owner_only'] = false;
        m['visibility'] = state == 'public'
            ? 'everyone'
            : state; // followers / friends
      }
      return m;
    }).toList();
    _notifyStories();
  }

  /// Bila filter aktif & slide tak lagi cocok, buang dari list tampil.
  /// (Dipanggil UI saat perlu; sederhana: biarkan sampai refetch berikut.)
}
