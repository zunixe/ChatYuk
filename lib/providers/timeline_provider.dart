import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/timeline_service.dart';
import '../services/message_cache.dart';

/// Cache per-scope: posts + pagination state untuk tab Semua/Mengikuti/Postinganku.
class _ScopeCache {
  final List<Map<String, dynamic>> posts;
  final DateTime? cursor;
  final bool cursorBoosted;
  final bool hasMore;
  _ScopeCache({
    required this.posts,
    this.cursor,
    this.cursorBoosted = false,
    this.hasMore = true,
  });
}

/// State timeline: feed, like/comment/share/boost, biaya boost.
class TimelineProvider extends ChangeNotifier {
  final TimelineService _service = TimelineService(Supabase.instance.client);

  final List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _postsView = const [];
  bool _loading = false;
  bool _hasMore = true;
  DateTime? _cursor;
  bool _cursorBoosted = false;
  String _scope = 'all';
  Set<String> _followedIds = {};
  Set<String> _subscribedIds = {};
  Set<String> _blockedIds = {};

  // Cache per scope — emit instant saat tab switch, server menyusul.
  final Map<String, _ScopeCache> _scopeCache = {};
  // Cache komentar per postId — buka comment instant, server menyusul.
  final Map<String, List<Map<String, dynamic>>> _commentCache = {};

  int _boostPaid = 50;
  int _boostBonus = 150;
  int _postsDailyLimit = 5;
  int get boostPaid => _boostPaid;
  int get boostBonus => _boostBonus;
  int get postsDailyLimit => _postsDailyLimit;

  StreamSubscription<Map<String, dynamic>>? _rtSub;
  StreamSubscription<AuthState>? _authSub;

  /// View yang di-cache — identity berubah HANYA saat data berubah,
  /// supaya `context.select` tidak rebuild tiap notify.
  List<Map<String, dynamic>> get posts => _postsView;
  bool get loading => _loading;
  bool get hasMore => _hasMore;

  TimelineProvider() {
    _listenRealtime();
    refreshPricing();
    _loadDiskScope('all');
    // Supabase signOut men-teardown semua channel realtime — subscribe
    // ulang saat user baru login supaya live-update timeline tetap jalan.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) {
        _listenRealtime();
        _refreshVisibilitySets();
      }
    });
  }

  // ── Persist feed ke disk (encrypted) — cold start tampil instan ──────────
  Timer? _diskSaveTimer;

  Map<String, dynamic> _postForDisk(Map<String, dynamic> p) => {
    for (final e in p.entries)
      e.key: (e.key == 'createdAt' && e.value is DateTime)
          ? (e.value as DateTime).toIso8601String()
          : e.value,
  };

  void _scheduleDiskSave() {
    _diskSaveTimer?.cancel();
    _diskSaveTimer = Timer(const Duration(seconds: 2), () {
      final rows = _scopeCache[_scope]?.posts;
      if (rows == null || rows.isEmpty) return;
      MessageCache.instance.saveRawObj(
        'timeline_$_scope',
        {
          'posts': rows.map(_postForDisk).toList(),
          'cursor': _cursor?.toIso8601String(),
          'cursorBoosted': _cursorBoosted,
          'hasMore': _hasMore,
        },
      );
    });
  }

  Future<void> _loadDiskScope(String scope, {bool notify = true}) async {
    try {
      final obj = await MessageCache.instance.loadRawObj('timeline_$scope');
      final rawPosts = obj['posts'];
      if (rawPosts is! List || rawPosts.isEmpty) return;
      if (_scopeCache[scope] != null && _scopeCache[scope]!.posts.isNotEmpty) {
        return; // sudah ada data lebih baru
      }
      final posts = rawPosts.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _scopeCache[scope] = _ScopeCache(
        posts: posts,
        cursor: DateTime.tryParse('${obj['cursor']}'),
        cursorBoosted: obj['cursorBoosted'] == true,
        hasMore: obj['hasMore'] != false,
      );
      if (scope == _scope && _posts.isEmpty && notify) {
        _posts
          ..clear()
          ..addAll(posts);
        _cursor = _scopeCache[scope]!.cursor;
        _cursorBoosted = _scopeCache[scope]!.cursorBoosted;
        _hasMore = _scopeCache[scope]!.hasMore;
        _invalidateView();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[TimelineProvider] disk load error: $e');
    }
  }

  void _listenRealtime() {
    _rtSub?.cancel();
    _rtSub = _service.watchNewPosts().listen(_onNewPost);
  }

  void _onNewPost(Map<String, dynamic> msg) {
    final event = msg['event'] as String? ?? 'insert';
    final row = msg['row'] as Map<String, dynamic>?;
    if (row == null || row.isEmpty) return;
    if (event == 'delete') {
      final id = row['id'];
      if (id != null) removePost('$id');
      return;
    }
    final id = row['id'];
    if (id == null) return;
    final existingIdx = _posts.indexWhere((p) => p['id'] == id);
    if (event == 'update') {
      if (existingIdx >= 0) {
        // Update counter (like/comment/share) + isBoosted dari row terbaru.
        final cur = _posts[existingIdx];
        _posts[existingIdx] = {
          ...cur,
          'likeCount': row['like_count'] ?? cur['likeCount'],
          'commentCount': row['comment_count'] ?? cur['commentCount'],
          'shareCount': row['share_count'] ?? cur['shareCount'],
          'isBoosted': row['is_boosted'] ?? cur['isBoosted'],
        };
        _invalidateView();
        notifyListeners();
      }
      return;
    }
    if (_posts.any((p) => p['id'] == id)) return;
    final p = _mapRow(row);
    if (p == null) return;

    // Filter scope: post yang TIDAK visible di scope aktif tidak boleh
    // masuk feed (realtime mengirim SEMUA insert di tabel posts).
    final authorId = row['author_id'];
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (_scope == 'mine') {
      if (authorId != me) return;
    } else if (_scope == 'following') {
      // Hanya post dari yang DI-FOLLOW — post sendiri tidak tampil di sini.
      if (authorId == null || authorId == me) return;
      if (!_followedIds.contains('$authorId')) return;
    } else {
      // scope 'all': cek visibilitas & blokir (sama seperti SQL list_posts).
      final author = '$authorId';
      if (_blockedIds.contains(author)) return;
      final visibility = row['visibility'] ?? 'public';
      if (visibility == 'subscribers' &&
          author != me &&
          !_subscribedIds.contains(author)) {
        return;
      }
      if (visibility == 'followers' &&
          author != me &&
          !_followedIds.contains(author) &&
          !_subscribedIds.contains(author)) {
        return;
      }
    }
    _posts.insert(0, p);
    _invalidateView();
    _syncScopeCache();
    notifyListeners();
  }

  /// Konversi row DB (snake_case) dari realtime → bentuk PostCard (camelCase).
  Map<String, dynamic>? _mapRow(Map<String, dynamic> row) {
    final createdAt = row['created_at'];
    if (createdAt == null) return null;
    final images = row['images'];
    return {
      'id': row['id'],
      'authorId': row['author_id'],
      'authorName': row['author_name'] ?? 'Anon',
      'authorGender': row['author_gender'] ?? 'other',
      'text': row['text'] ?? '',
      'imagePath': row['image_path'] ?? '',
      'images': images is List ? images : null,
      'visibility': row['visibility'] ?? 'public',
      'likeCount': row['like_count'] ?? 0,
      'commentCount': row['comment_count'] ?? 0,
      'shareCount': row['share_count'] ?? 0,
      'isBoosted': row['is_boosted'] == true,
      'createdAt': createdAt,
      // Realtime tidak membawa authorAvatar — fetch via ProfileAvatar fallback.
      'authorAvatar': '',
      'isLiked': false,
      'isFollowing': row['is_following'] == true,
      'isFriend': false,
    };
  }

  void _invalidateView() {
    _postsView = List.unmodifiable(_posts);
  }

  /// Simpan state _posts + pagination ke cache scope aktif.
  void _syncScopeCache() {
    _scopeCache[_scope] = _ScopeCache(
      posts: List.from(_posts),
      cursor: _cursor,
      cursorBoosted: _cursorBoosted,
      hasMore: _hasMore,
    );
  }

  // --- Comment cache API ---

  /// Ambil cache komentar per postId (null = belum pernah di-load).
  List<Map<String, dynamic>>? getCachedComments(String postId) =>
      _commentCache[postId];

  /// Simpan hasil fetch komentar ke cache.
  void cacheComments(String postId, List<Map<String, dynamic>> comments) {
    _commentCache[postId] = List.from(comments);
  }

  /// Tambah satu komentar baru ke cache (setelah submit berhasil).
  void addCommentToCache(String postId, Map<String, dynamic> comment) {
    final existing = _commentCache[postId];
    if (existing != null) {
      _commentCache[postId] = [...existing, comment];
    }
  }

  /// Hapus komentar optimistic (rollback jika gagal) dari cache.
  void removeCommentFromCache(String postId, dynamic commentId) {
    final existing = _commentCache[postId];
    if (existing != null) {
      _commentCache[postId] = existing
          .where((c) => c['id'] != commentId)
          .toList();
    }
  }

  /// Ganti komentar optimistic dengan data server (konfirmasi).
  void replaceCommentInCache(
    String postId,
    dynamic oldId,
    Map<String, dynamic> newComment,
  ) {
    final existing = _commentCache[postId];
    if (existing != null) {
      _commentCache[postId] = [
        for (final c in existing)
          if (c['id'] == oldId) newComment else c,
      ];
    }
  }

  /// Hapus semua cache saat logout.
  void resetCache() {
    _diskSaveTimer?.cancel();
    _scopeCache.clear();
    _commentCache.clear();
    _posts.clear();
    _postsView = const [];
    _cursor = null;
    _cursorBoosted = false;
    _hasMore = true;
    _scope = 'all';
    for (final s in const ['all', 'following', 'mine']) {
      MessageCache.instance.removeRawObj('timeline_$s');
    }
  }

  Future<void> _refreshFollowedIds() async {
    try {
      final me = Supabase.instance.client.auth.currentUser?.id;
      if (me == null) return;
      final rows = await Supabase.instance.client
          .from('follows')
          .select('followee_id')
          .eq('follower_id', me);
      _followedIds = rows.map((r) => '${r['followee_id']}').toSet();
    } catch (e) {
      debugPrint('[TimelineProvider] followed ids error: $e');
    }
  }

  /// Set subscriber + blokir user aktif — dipakai filter realtime supaya
  /// post ber-visibilitas `subscribers`/`followers` dan post dari user yang
  /// di-blokir TIDAK bocor ke feed (SQL list_posts memfilter, realtime tidak).
  Future<void> _refreshVisibilitySets() async {
    try {
      final me = Supabase.instance.client.auth.currentUser?.id;
      if (me == null) return;
      final subs = await Supabase.instance.client
          .from('subscriptions')
          .select('creator_id')
          .eq('subscriber_id', me)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String());
      _subscribedIds = subs.map((r) => '${r['creator_id']}').toSet();
      final blocks = await Supabase.instance.client
          .from('blocks')
          .select('blocker_id,blocked_id')
          .or('blocker_id.eq.$me,blocked_id.eq.$me');
      _blockedIds = blocks.map((r) {
        final b = '${r['blocker_id']}';
        final d = '${r['blocked_id']}';
        return b == me ? d : b;
      }).toSet();
    } catch (e) {
      debugPrint('[TimelineProvider] visibility sets error: $e');
    }
  }

  Future<void> refreshPricing() async {
    try {
      final p = await _service.pricing();
      _boostPaid = (p['boost_paid'] as num?)?.toInt() ?? _boostPaid;
      _boostBonus = (p['boost_bonus'] as num?)?.toInt() ?? _boostBonus;
      _postsDailyLimit =
          (p['posts_daily_limit'] as num?)?.toInt() ?? _postsDailyLimit;
      notifyListeners();
    } catch (e) {
      debugPrint('[TimelineProvider] pricing error: $e');
    }
  }

  Future<void> load(String scope, {bool refresh = false}) async {
    // Kalau sedang loading scope LAIN, tetap emit cache scope baru dulu
    // supaya tab switch terasa instant, lalu lanjut fetch setelah selesai.
    if (_loading && _scope == scope) return;
    _scope = scope;
    if (refresh) {
      _cursor = null;
      _cursorBoosted = false;
      _hasMore = true;
      // Cache daftar followee — dipakai filter realtime untuk scope
      // 'following' (payload realtime tidak membawa is_following).
      if (scope == 'following') _refreshFollowedIds();
      // Cache subscriber + blokir (dan followee) untuk filter visibilitas
      // feed realtime di scope 'all'/'following'.
      if (scope == 'all') {
        _refreshFollowedIds();
        _refreshVisibilitySets();
      }
      // Emit cache scope baru DULU — instant tanpa network.
      // Konten tab sebelumnya diganti atomik dengan cache tab baru.
      // Server menyusul dan update feed dengan data fresh.
      final cached = _scopeCache[scope];
      if (cached != null && cached.posts.isNotEmpty) {
        _posts
          ..clear()
          ..addAll(cached.posts);
        _cursor = cached.cursor;
        _cursorBoosted = cached.cursorBoosted;
        _hasMore = cached.hasMore;
        _invalidateView();
        notifyListeners(); // frame pertama instant dari cache
      } else {
        // Cache memori kosong (cold start) — coba disk.
        _loadDiskScope(scope);
      }
      // Kalau tidak ada cache: biarkan _posts apa adanya (konten scope lama
      // tetap tampil selama fetch) supaya tidak pernah blink ke empty state.
    }
    _loading = true;
    notifyListeners();
    try {
      final list = await _service.listPosts(
        scope,
        cursor: refresh ? null : _cursor,
        cursorBoosted: refresh ? false : _cursorBoosted,
      );
      if (list.isEmpty) {
        _hasMore = false;
        if (refresh) {
          _posts.clear();
          _invalidateView();
          // Hapus cache scope ini — memang kosong dari server.
          _scopeCache.remove(scope);
        }
      } else {
        final now = DateTime.now();
        if (refresh) {
          // Ganti seluruh feed dengan halaman pertama yang fresh (atomik).
          _posts
            ..clear()
            ..addAll(list);
        } else {
          final seen = _posts.map((p) => p['id']).toSet();
          for (final p in list) {
            if (!seen.contains(p['id'])) _posts.add(p);
          }
        }
        // Cursor keyset konsisten dengan ORDER BY (is_boosted desc, created_at desc).
        final last = list.last;
        final lastCreated = last['createdAt'];
        // RPC list_posts mengembalikan createdAt sebagai String ISO-8601
        // (jsonb_build_object), BUKAN DateTime — parse dulu, kalau gagal
        // fallback now (halaman berikutnya tetap jalan, bukan stuck).
        _cursor = lastCreated is DateTime
            ? lastCreated
            : (DateTime.tryParse('$lastCreated') ?? now);
        _cursorBoosted = last['isBoosted'] == true;
        // Halaman lebih pendek dari limit → sudah ujung feed.
        if (list.length < 30) _hasMore = false;
        _invalidateView();
      }
      // Simpan hasil fetch terbaru ke cache scope ini.
      _syncScopeCache();
      _scheduleDiskSave();
    } catch (e) {
      debugPrint('[TimelineProvider] load error: $e');
      _hasMore = false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Mutasi lokal setelah aksi sukses (tanpa refetch penuh).
  void updatePost(String id, Map<String, dynamic> patch) {
    final i = _posts.indexWhere((p) => p['id'] == id);
    if (i >= 0) {
      _posts[i] = {..._posts[i], ...patch};
      _invalidateView();
      _syncScopeCache();
      notifyListeners();
    }
  }

  void removePost(String id) {
    _posts.removeWhere((p) => p['id'] == id);
    _invalidateView();
    _syncScopeCache();
    notifyListeners();
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}
