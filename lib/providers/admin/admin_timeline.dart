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
      // RPC mengembalikan kolom snake_case (author_name, like_count, dst),
      // tapi PostCard membaca kunci camelCase (authorName, likeCount, …) —
      // tanpa konversi ini semua kartu jatuh ke fallback 'Anon' dan angka
      // like/komentar = 0. Samakan bentuknya dengan timeline_provider._mapRow.
      _adminPosts = list.map(_mapPostRow).toList();
      _postsLoaded = true;
    } catch (e) {
      dlog('[Admin] fetchPosts error: $e');
      // Pertahankan data lama bila ada (jangan kosongkan saat error).
    } finally {
      _postsLoading = false;
      _notifyPosts();
    }
  }

  /// Baris RPC snake_case → map camelCase yang dipahami [PostCard]
  /// (identik dengan timeline_provider._mapRow). `id`/`visibility` dipertahankan
  /// karena `_visibilityBar`/`setPostVisibility` memakainya.
  Map<String, dynamic> _mapPostRow(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'authorId': row['author_id'],
      'authorName': row['author_name'] ?? 'Anon',
      'authorGender': row['author_gender'] ?? 'other',
      'authorAvatar': '',
      'text': row['text'] ?? '',
      'imagePath': row['image_path'] ?? '',
      'images': row['images'] is List ? row['images'] : null,
      'imageW': (row['image_w'] as num?)?.toInt() ?? 0,
      'imageH': (row['image_h'] as num?)?.toInt() ?? 0,
      'imageDims': row['image_dims'] is List ? row['image_dims'] : null,
      'imageBlurhashes':
          row['image_blurhashes'] is List ? row['image_blurhashes'] : null,
      'visibility': row['visibility'] ?? 'public',
      'likeCount': row['like_count'] ?? 0,
      'commentCount': row['comment_count'] ?? 0,
      'shareCount': row['share_count'] ?? 0,
      'isBoosted': row['is_boosted'] == true,
      'createdAt': row['created_at'],
      'isLiked': false,
      'isFollowing': false,
    };
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
