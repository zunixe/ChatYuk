import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/cache/message_cache.dart';
import '../../core/perf/perf_probe.dart';
import '../../services/rt_resilient.dart';
import '../../services/timeline_service.dart';
import '../../utils.dart';

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

/// State timeline (immutable — yang di-watch widget).
class TimelineState {
  final List<Map<String, dynamic>> posts;
  final bool loading;
  final bool hasMore;
  final bool fetchFailed;
  final int boostPaid;
  final int boostBonus;
  final int postsDailyLimit;

  const TimelineState({
    this.posts = const [],
    this.loading = true,
    this.hasMore = true,
    this.fetchFailed = false,
    this.boostPaid = 50,
    this.boostBonus = 150,
    this.postsDailyLimit = 5,
  });

  @override
  bool operator ==(Object other) =>
      other is TimelineState &&
      other.loading == loading &&
      other.hasMore == hasMore &&
      other.fetchFailed == fetchFailed &&
      other.boostPaid == boostPaid &&
      other.boostBonus == boostBonus &&
      other.postsDailyLimit == postsDailyLimit &&
      listEquals(other.posts, posts);

  @override
  int get hashCode => Object.hash(
        loading,
        hasMore,
        fetchFailed,
        boostPaid,
        boostBonus,
        postsDailyLimit,
        Object.hashAll(posts),
      );
}

/// State timeline: feed, like/comment/share/boost, biaya boost (Riverpod).
/// Migrasi dari ChangeNotifier → Notifier. Global (persist sepanjang sesi).
class TimelineNotifier extends Notifier<TimelineState> {
  final TimelineService _service;
  final SupabaseClient _sb;

  TimelineNotifier({TimelineService? service, SupabaseClient? sb, bool autoInit = true})
      : _sb = sb ?? Supabase.instance.client,
        _service =
            service ?? TimelineService(sb ?? Supabase.instance.client),
        _autoInit = autoInit;

  final bool _autoInit;

  final List<Map<String, dynamic>> _posts = [];
  static const int _maxMemPosts = 120;
  void _capPosts() {
    while (_posts.length > _maxMemPosts) {
      _posts.removeLast();
    }
  }

  bool _loading = true;
  final Map<String, Future<void>> _inFlight = {};
  bool _hasMore = true;
  DateTime? _cursor;
  bool _cursorBoosted = false;
  String _scope = 'all';
  bool _lastFetchFailed = false;
  String _scopeError = 'all';
  Set<String> _followedIds = {};
  Set<String> _subscribedIds = {};
  Set<String> _blockedIds = {};
  DateTime? _visibilityAt;
  static const _visibilityTtl = Duration(seconds: 60);

  final Map<String, _ScopeCache> _scopeCache = {};
  static const _scopeFreshTtl = Duration(seconds: 90);
  final Map<String, DateTime> _lastLoadedAt = {};
  final Map<String, List<Map<String, dynamic>>> _commentCache = {};
  final Map<String, DateTime> _commentCacheAt = {};
  static const _commentTtl = Duration(seconds: 30);

  int _boostPaid = 50;
  int _boostBonus = 150;
  int _postsDailyLimit = 5;

  StreamSubscription<Map<String, dynamic>>? _rtSub;
  StreamSubscription<AuthState>? _authSub;
  Timer? _diskSaveTimer;
  Timer? _prefetchTimer;
  DateTime? _followedIdsAt;
  static const _followedIdsTtl = Duration(seconds: 60);
  static const int _commentPostCap = 20;

  @override
  TimelineState build() {
    ref.onDispose(_disposeAll);
    if (!_autoInit) return const TimelineState();
    _listenRealtime();
    refreshPricing();
    for (final s in const ['all', 'following', 'mine']) {
      _loadDiskScope(s);
    }
    _authSub = _sb.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) {
        _listenRealtime();
        _refreshVisibilitySets();
      }
    }, onError: (e) => dlog('[TimelineProvider] auth stream error: $e'));
    return const TimelineState();
  }

  var _disposed = false;

  void _emit() {
    if (_disposed) return;
    state = TimelineState(
      posts: List.unmodifiable(_postsView),
      loading: _loading,
      hasMore: _hasMore,
      fetchFailed: _lastFetchFailed && _scopeError == _scope,
      boostPaid: _boostPaid,
      boostBonus: _boostBonus,
      postsDailyLimit: _postsDailyLimit,
    );
  }

  // ── Getter kompat ──
  List<Map<String, dynamic>> get posts => _postsView;
  bool get loading => _loading;
  bool get hasMore => _hasMore;
  bool get fetchFailed => _lastFetchFailed && _scopeError == _scope;
  int get boostPaid => _boostPaid;
  int get boostBonus => _boostBonus;
  int get postsDailyLimit => _postsDailyLimit;
  List<Map<String, dynamic>> _postsView = const [];
  void _invalidateView() {
    _postsView = List.unmodifiable(_posts);
  }

  // ── Passthrough (Fase 9b) ──
  Future<Map<String, dynamic>> createPost({
    required String text,
    List<String> imagePaths = const [],
    List<Map<String, int>> imageDims = const [],
    String visibility = 'public',
  }) =>
      PerfProbe.timed(
        'timeline.createPost',
        () => _service.createPost(
          text: text,
          imagePaths: imagePaths,
          imageDims: imageDims,
          visibility: visibility,
        ),
      );

  Future<Map<String, dynamic>> toggleLike(String postId) =>
      PerfProbe.timed('timeline.like', () => _service.toggleLike(postId));
  Future<Map<String, dynamic>> addComment(String postId, String text) =>
      PerfProbe.timed(
          'timeline.addComment', () => _service.addComment(postId, text));
  Future<Map<String, dynamic>> replyComment(
    String postId,
    int parentId,
    String text,
  ) =>
      PerfProbe.timed(
        'timeline.replyComment',
        () => _service.replyComment(postId, parentId, text),
      );
  Future<Map<String, dynamic>> sharePost(String postId) =>
      PerfProbe.timed('timeline.share', () => _service.sharePost(postId));
  Future<Map<String, dynamic>> boostPost(String postId) =>
      _service.boostPost(postId);
  Future<void> deletePost(String postId) => _service.deletePost(postId);
  Future<Map<String, dynamic>?> getPost(String postId) =>
      PerfProbe.timed('timeline.getPost', () => _service.getPost(postId));
  Future<List<Map<String, dynamic>>> comments(String postId) =>
      PerfProbe.timed('timeline.comments', () => _service.comments(postId));
  Future<Map<String, dynamic>> toggleCommentLike(int commentId) =>
      _service.toggleCommentLike(commentId);
  Future<Map<String, dynamic>> shareComment(int commentId) =>
      _service.shareComment(commentId);

  void invalidateFollowedIds() => _followedIdsAt = null;

  Map<String, dynamic> _postForDisk(Map<String, dynamic> p) => {
        for (final e in p.entries)
          e.key: (e.key == 'createdAt' && e.value is DateTime)
              ? (e.value as DateTime).toIso8601String()
              : e.value,
      };

  void _scheduleDiskSave([String? scope]) {
    final target = scope ?? _scope;
    _diskSaveTimer?.cancel();
    _diskSaveTimer = Timer(const Duration(seconds: 2), () {
      final rows = _scopeCache[target]?.posts;
      if (rows == null || rows.isEmpty) return;
      MessageCache.instance.saveRawObj(
        'timeline_$target',
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
      if (rawPosts is! List || rawPosts.isEmpty) {
        return;
      }
      if (_scopeCache[scope] != null && _scopeCache[scope]!.posts.isNotEmpty) {
        return;
      }
      final posts =
          rawPosts.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _scopeCache[scope] = _ScopeCache(
        posts: posts,
        cursor: DateTime.tryParse('${obj['cursor']}'),
        cursorBoosted: obj['cursorBoosted'] == true,
        hasMore: obj['hasMore'] != false,
      );
      if (scope == _scope && _posts.isEmpty && notify) {
        _posts
          ..clear()
          ..addAll(_excludeOwn(posts, scope));
        _capPosts();
        _cursor = _scopeCache[scope]!.cursor;
        _cursorBoosted = _scopeCache[scope]!.cursorBoosted;
        _hasMore = _scopeCache[scope]!.hasMore;
        _invalidateView();
        _emit();
      }
    } catch (e) {
      dlog('[TimelineProvider] disk load error: $e');
    }
  }

  void _listenRealtime() {
    _rtSub?.cancel();
    _rtSub = listenResilient(
      () => _service.watchNewPosts(),
      _onNewPost,
      isDisposed: () => false,
      onError: (e) => dlog('[TimelineProvider] realtime error: $e'),
    );
  }

  @visibleForTesting
  void debugOnNewPost(Map<String, dynamic> msg) => _onNewPost(msg);

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
      if (existingIdx < 0) return;
      final cur = _posts[existingIdx];
      final next = {
        ...cur,
        'likeCount': row['like_count'] ?? cur['likeCount'],
        'commentCount': row['comment_count'] ?? cur['commentCount'],
        'shareCount': row['share_count'] ?? cur['shareCount'],
        'isBoosted': row['is_boosted'] ?? cur['isBoosted'],
      };
      if (next['likeCount'] == cur['likeCount'] &&
          next['commentCount'] == cur['commentCount'] &&
          next['shareCount'] == cur['shareCount'] &&
          next['isBoosted'] == cur['isBoosted']) {
        return;
      }
      _posts[existingIdx] = next;
      _invalidateView();
      _syncScopeCache();
      _emit();
      return;
    }
    if (_posts.any((p) => p['id'] == id)) return;
    final p = _mapRow(row);
    if (p == null) return;

    final authorId = row['author_id'];
    final me = _sb.auth.currentUser?.id;
    if (_scope == 'mine') {
      if (authorId != me) return;
    } else if (_scope == 'following') {
      if (authorId == null || authorId == me) return;
      if (!_followedIds.contains('$authorId')) return;
    } else {
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
    _capPosts();
    _invalidateView();
    _syncScopeCache();
    _emit();
  }

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
      'imageW': (row['image_w'] as num?)?.toInt() ?? 0,
      'imageH': (row['image_h'] as num?)?.toInt() ?? 0,
      'imageDims': row['image_dims'] is List ? row['image_dims'] : null,
      'visibility': row['visibility'] ?? 'public',
      'likeCount': row['like_count'] ?? 0,
      'commentCount': row['comment_count'] ?? 0,
      'shareCount': row['share_count'] ?? 0,
      'isBoosted': row['is_boosted'] == true,
      'createdAt': createdAt,
      'authorAvatar': '',
      'isLiked': false,
      'isFollowing': row['is_following'] == true,
    };
  }

  void _syncScopeCache() {
    _scopeCache[_scope] = _ScopeCache(
      posts: List.from(_posts),
      cursor: _cursor,
      cursorBoosted: _cursorBoosted,
      hasMore: _hasMore,
    );
  }

  List<Map<String, dynamic>>? getCachedComments(String postId) =>
      _commentCache[postId];

  bool isCommentsFresh(String postId) {
    final at = _commentCacheAt[postId];
    if (at == null) return false;
    return DateTime.now().difference(at) < _commentTtl;
  }

  bool hasCommentsCache(String postId) => _commentCache.containsKey(postId);

  void cacheComments(String postId, List<Map<String, dynamic>> comments) {
    _commentCache[postId] = List.from(comments);
    _commentCacheAt[postId] = DateTime.now();
    while (_commentCache.length > _commentPostCap) {
      final oldest = _commentCache.keys.first;
      _commentCache.remove(oldest);
      _commentCacheAt.remove(oldest);
    }
  }

  void addCommentToCache(String postId, Map<String, dynamic> comment) {
    final existing = _commentCache[postId];
    if (existing != null) {
      _commentCache[postId] = [...existing, comment];
    }
  }

  void removeCommentFromCache(String postId, dynamic commentId) {
    final existing = _commentCache[postId];
    if (existing != null) {
      _commentCache[postId] =
          existing.where((c) => c['id'] != commentId).toList();
    }
  }

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

  Future<void> deleteComment(String postId, int commentId) async {
    await _service.deleteComment(commentId);
    removeCommentFromCache(postId, commentId);
    final i = _posts.indexWhere((p) => p['id'] == postId);
    if (i >= 0) {
      final cur = ((_posts[i]['commentCount'] as num?)?.toInt() ?? 1);
      updatePost(postId, {'commentCount': (cur - 1).clamp(0, 1 << 31)});
    }
  }

  void resetCache() {
    _diskSaveTimer?.cancel();
    _inFlight.clear();
    _scopeCache.clear();
    _commentCache.clear();
    _commentCacheAt.clear();
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

  Future<void> _refreshFollowedIds({bool force = false}) async {
    if (!force &&
        _followedIdsAt != null &&
        DateTime.now().difference(_followedIdsAt!) < _followedIdsTtl) {
      return;
    }
    try {
      final me = _sb.auth.currentUser?.id;
      if (me == null) return;
      final rows = await _sb
          .from('follows')
          .select('followee_id')
          .eq('follower_id', me);
      _followedIds = rows.map((r) => '${r['followee_id']}').toSet();
      _followedIdsAt = DateTime.now();
    } catch (e) {
      dlog('[TimelineProvider] followed ids error: $e');
    }
  }

  Future<void> _refreshVisibilitySets({bool force = false}) async {
    if (!force &&
        _visibilityAt != null &&
        DateTime.now().difference(_visibilityAt!) < _visibilityTtl) {
      return;
    }
    try {
      final me = _sb.auth.currentUser?.id;
      if (me == null) return;
      final subs = await _sb
          .from('subscriptions')
          .select('creator_id')
          .eq('subscriber_id', me)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String());
      _subscribedIds = subs.map((r) => '${r['creator_id']}').toSet();
      final blocks = await _sb
          .from('blocks')
          .select('blocker_id,blocked_id')
          .or('blocker_id.eq.$me,blocked_id.eq.$me');
      _blockedIds = blocks.map((r) {
        final b = '${r['blocker_id']}';
        final d = '${r['blocked_id']}';
        return b == me ? d : b;
      }).toSet();
      _visibilityAt = DateTime.now();
    } catch (e) {
      dlog('[TimelineProvider] visibility sets error: $e');
    }
  }

  Future<void> refreshPricing() async {
    try {
      final p = await _service.pricing();
      _boostPaid = (p['boost_paid'] as num?)?.toInt() ?? _boostPaid;
      _boostBonus = (p['boost_bonus'] as num?)?.toInt() ?? _boostBonus;
      _postsDailyLimit =
          (p['posts_daily_limit'] as num?)?.toInt() ?? _postsDailyLimit;
      _emit();
    } catch (e) {
      dlog('[TimelineProvider] pricing error: $e');
    }
  }

  Future<void> prewarm() async {
    await Future.wait([
      for (final s in const ['all', 'following', 'mine'])
        if (_lastLoadedAt[s] == null) _fetchScope(s, refresh: true),
    ]);
  }

  Future<void> _fetchScope(String scope, {required bool refresh}) async {
    final inFlight = _inFlight[scope];
    if (inFlight != null) return inFlight;
    final fut = _fetchScopeInner(scope, refresh: refresh);
    _inFlight[scope] = fut;
    try {
      await fut;
    } finally {
      _inFlight.remove(scope);
    }
  }

  bool _prepareVisible(String scope) {
    _scope = scope;
    _lastFetchFailed = false;
    _cursor = null;
    _cursorBoosted = false;
    _hasMore = true;
    final cached = _scopeCache[scope];
    final fresh = cached != null &&
        cached.posts.isNotEmpty &&
        _lastLoadedAt[scope] != null &&
        DateTime.now().difference(_lastLoadedAt[scope]!) < _scopeFreshTtl;
    if (fresh) {
      _posts
        ..clear()
        ..addAll(_excludeOwn(cached.posts, scope));
      _cursor = cached.cursor;
      _cursorBoosted = cached.cursorBoosted;
      _hasMore = cached.hasMore;
      _invalidateView();
      _emit();
      return true;
    }
    if (cached != null && cached.posts.isNotEmpty) {
      _posts
        ..clear()
        ..addAll(_excludeOwn(cached.posts, scope));
      _cursor = cached.cursor;
      _cursorBoosted = cached.cursorBoosted;
      _hasMore = cached.hasMore;
      _invalidateView();
    } else {
      _posts.clear();
      _invalidateView();
      _loadDiskScope(scope);
      _loading = true;
    }
    if (scope == 'following') _refreshFollowedIds();
    if (scope == 'all') {
      _refreshFollowedIds();
      _refreshVisibilitySets();
    }
    _emit();
    return false;
  }

  List<Map<String, dynamic>> _excludeOwn(
      List<Map<String, dynamic>> posts, String scope) {
    if (scope != 'following') return posts;
    final me = _sb.auth.currentUser?.id;
    if (me == null) return posts;
    return posts.where((p) => '${p['authorId']}' != me).toList();
  }

  Future<void> load(
    String scope, {
    bool refresh = false,
    bool skipIfFresh = false,
  }) async {
    if (refresh) {
      final fresh = _prepareVisible(scope);
      if (skipIfFresh && fresh) return;
    }
    final fut = _fetchScope(scope, refresh: refresh);
    if (refresh) {
      await Future.any([
        fut,
        Future<void>.delayed(const Duration(seconds: 3)),
      ]);
      return;
    }
    await fut;
  }

  Future<void> _fetchScopeInner(String scope, {required bool refresh}) async {
    final active = _scope == scope;
    try {
      final fetched = await PerfProbe.timed(
        refresh ? 'timeline.rpc' : 'timeline.rpcMore',
        () => _service
            .listPosts(
              scope,
              cursor: refresh ? null : _cursor,
              cursorBoosted: refresh ? false : _cursorBoosted,
            )
            .timeout(const Duration(seconds: 10)),
      );
      final list = _excludeOwn(fetched, scope);
      if (list.isEmpty) {
        if (active) _hasMore = false;
        if (refresh) {
          _scopeCache.remove(scope);
          if (active) {
            _posts.clear();
            _invalidateView();
          }
        }
      } else {
        final last = list.last;
        final lastCreated = last['createdAt'];
        final cursor = lastCreated is DateTime
            ? lastCreated
            : (DateTime.tryParse('$lastCreated') ?? DateTime.now());
        final boosted = last['isBoosted'] == true;
        final more = list.length >= 30;
        if (active) {
          if (refresh) {
            _posts
              ..clear()
              ..addAll(list);
          } else {
            final seen = _posts.map((p) => p['id']).toSet();
            for (final p in list) {
              if (!seen.contains(p['id'])) _posts.add(p);
            }
          }
          _capPosts();
          _cursor = cursor;
          _cursorBoosted = boosted;
          _hasMore = more;
          _invalidateView();
          _syncScopeCache();
          _prefetchComments();
        } else {
          _scopeCache[scope] = _ScopeCache(
            posts: list,
            cursor: cursor,
            cursorBoosted: boosted,
            hasMore: more,
          );
        }
      }
      _lastLoadedAt[scope] = DateTime.now();
      _scheduleDiskSave(scope);
    } catch (e) {
      dlog('[TimelineProvider] load $scope error: $e');
      if (_scope == scope) {
        _lastFetchFailed = true;
        _scopeError = scope;
      }
    } finally {
      if (_scope == scope) _loading = false;
      _emit();
    }
  }

  void _prefetchComments() {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(milliseconds: 500), () {
      if (_scope.isEmpty) return;
      var n = 0;
      for (final p in _posts) {
        if (n >= 2) break;
        final id = '${p['id'] ?? ''}';
        final cc = (p['commentCount'] as num?)?.toInt() ?? 0;
        if (id.isEmpty || cc <= 0 || _commentCache.containsKey(id)) continue;
        n++;
        unawaited(_fetchCommentsBg(id));
      }
    });
  }

  Future<void> _fetchCommentsBg(String postId) async {
    try {
      final list = await _service
          .comments(postId)
          .timeout(const Duration(seconds: 10));
      if (!_commentCache.containsKey(postId)) {
        _commentCache[postId] = list;
        _commentCacheAt[postId] = DateTime.now();
      }
    } catch (_) {}
  }

  void refreshAvatarForUid(String uid, String newBase64) {
    if (uid.isEmpty) return;
    var changed = false;
    for (var i = 0; i < _posts.length; i++) {
      if ('${_posts[i]['authorId']}' == uid) {
        _posts[i] = {..._posts[i], 'authorAvatar': newBase64};
        changed = true;
      }
    }
    for (final entry in _scopeCache.entries) {
      final list = entry.value.posts;
      for (var i = 0; i < list.length; i++) {
        if ('${list[i]['authorId']}' == uid) {
          list[i] = {...list[i], 'authorAvatar': newBase64};
        }
      }
    }
    _scheduleDiskSave();
    if (changed) {
      _invalidateView();
      _emit();
    } else {
      _emit();
    }
  }

  void updatePost(String id, Map<String, dynamic> patch) {
    final i = _posts.indexWhere((p) => p['id'] == id);
    if (i >= 0) {
      _posts[i] = {..._posts[i], ...patch};
      _invalidateView();
      _syncScopeCache();
      _emit();
    }
  }

  void removePost(String id) {
    _posts.removeWhere((p) => p['id'] == id);
    _invalidateView();
    _syncScopeCache();
    _emit();
  }

  void _disposeAll() {
    _disposed = true;
    _rtSub?.cancel();
    _authSub?.cancel();
    _prefetchTimer?.cancel();
    _diskSaveTimer?.cancel();
  }
}

final timelineProvider =
    NotifierProvider<TimelineNotifier, TimelineState>(TimelineNotifier.new);
