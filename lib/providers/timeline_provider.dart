import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/timeline_service.dart';
import '../services/rt_resilient.dart';
import '../core/cache/message_cache.dart';
import '../core/perf/perf_probe.dart';

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
  bool _disposed = false;

  // Service di-inject untuk test (default produksi) — call site tidak berubah.
  final TimelineService _service;

  final List<Map<String, dynamic>> _posts = [];
  List<Map<String, dynamic>> _postsView = const [];
  // TRUE sejak awal: frame pertama Timeline tidak boleh flash empty state
  // "Ketuk +" — tunggu disk/network selesai dulu (posts.isEmpty && loading
  // = spinner). Falsify hanya di load()/_loadDiskScope setelah sumber siap.
  bool _loading = true;
  // Future fetch per-scope yang sedang berjalan — dedupe antara klik tab,
  // pull-refresh, pagination, dan prewarm tanpa saling menimpa.
  final Map<String, Future<void>> _inFlight = {};
  bool _hasMore = true;
  DateTime? _cursor;
  bool _cursorBoosted = false;
  String _scope = 'all';
  // Error terakhir fetch scope aktif — dipakai UI membedakan "feed kosong"
  // (server sukses jawab kosong) vs "network error" (jangan tampilkan
  // empty state palsu; tawarkan tombol coba lagi).
  bool _lastFetchFailed = false;
  String _scopeError = 'all';
  Set<String> _followedIds = {};
  Set<String> _subscribedIds = {};
  Set<String> _blockedIds = {};
  DateTime? _visibilityAt;
  static const _visibilityTtl = Duration(seconds: 60);

  // Cache per scope — emit instant saat tab switch, server menyusul.
  final Map<String, _ScopeCache> _scopeCache = {};
  // Kapan terakhir scope ini sukses fetch dari server — tab yang masih
  // fresh (<30s) TIDAK di-fetch ulang saat diswitch (klik terasa instan,
  // pola sama dengan list chat).
  final Map<String, DateTime> _lastLoadedAt = {};
  // Cache komentar per postId — buka comment instant, server menyusul.
  final Map<String, List<Map<String, dynamic>>> _commentCache = {};
  // Waktu cache komentar diisi — dipakai TTL supaya buka-tutup-buka sheet
  // TIDAK menembak RPC berulang (dulu selalu fetch walau cache masih segar).
  final Map<String, DateTime> _commentCacheAt = {};
  static const _commentTtl = Duration(seconds: 30);

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

  /// Feed aktif gagal di-fetch (network/RPC error) — bukan kosong sungguhan.
  bool get fetchFailed => _lastFetchFailed && _scopeError == _scope;


  // ── Passthrough (Fase 9b) ──
  Future<Map<String, dynamic>> createPost({
    required String text,
    List<String> imagePaths = const [],
    String visibility = 'public',
  }) =>
      _service.createPost(text: text, imagePaths: imagePaths, visibility: visibility);

  // ── Passthrough aksi post (dipakai PostCard — hindari instansiasi
  //    TimelineService inline di widget, biar DI & testable) ──
  Future<Map<String, dynamic>> toggleLike(String postId) =>
      PerfProbe.timed('timeline.like', () => _service.toggleLike(postId));
  Future<Map<String, dynamic>> addComment(String postId, String text) =>
      PerfProbe.timed('timeline.addComment', () => _service.addComment(postId, text));
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
  Future<List<Map<String, dynamic>>> comments(String postId) =>
      PerfProbe.timed('timeline.comments', () => _service.comments(postId));
  Future<Map<String, dynamic>> toggleCommentLike(int commentId) =>
      _service.toggleCommentLike(commentId);
  Future<Map<String, dynamic>> shareComment(int commentId) =>
      _service.shareComment(commentId);

  /// Client Supabase — disuntik supaya test memakai client palsu.
  final SupabaseClient _sb;

  TimelineProvider({TimelineService? service, SupabaseClient? sb, bool autoInit = true})
      : _sb = sb ?? Supabase.instance.client,
        _service = service ?? TimelineService(sb ?? Supabase.instance.client) {
    if (!autoInit) return;
    _listenRealtime();
    refreshPricing();
    // Disk cache SEMUA scope — cold start tab mana pun tampil instan.
    for (final s in const ['all', 'following', 'mine']) {
      _loadDiskScope(s);
    }
    // Supabase signOut men-teardown semua channel realtime — subscribe
    // ulang saat user baru login supaya live-update timeline tetap jalan.
    _authSub = _sb.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) {
        _listenRealtime();
        _refreshVisibilitySets();
      }
    });
  }

  /// Follow/unfollow terjadi → buang TTL cache, fetch berikutnya segar.
  /// Dipanggil via SocialProvider.onFollowGraphChanged (di-wiring di app.dart).
  void invalidateFollowedIds() => _followedIdsAt = null;

  // ── Persist feed ke disk (encrypted) — cold start tampil instan ──────────
  Timer? _diskSaveTimer;

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
        // Disk kosong untuk scope ini — loading dibiarkan hidup sampai
        // network selesai (jangan flash empty state palsu).
        return;
      }
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
          ..addAll(_excludeOwn(posts, scope));
        _cursor = _scopeCache[scope]!.cursor;
        _cursorBoosted = _scopeCache[scope]!.cursorBoosted;
        _hasMore = _scopeCache[scope]!.hasMore;
        _invalidateView();
        if (!_disposed) notifyListeners();
      }
    } catch (e) {
      dlog('[TimelineProvider] disk load error: $e');
    }
  }

  void _listenRealtime() {
    _rtSub?.cancel();
    // Resilient: error channel me-restart subscription otomatis (post
    // baru berhenti masuk = feed terasa "mati" sampai restart).
    // SATU jalur broadcast: watchNewPosts (Postgres changes) membawa row
    // penuh (id/created_at/counter) — jalur Broadcast timeline-all dihapus
    // karena tidak ada producer (sendBroadcastMessage tak pernah dipanggil)
    // dan payload-nya berbentuk notifikasi, bukan row post.
    _rtSub = listenResilient(
      () => _service.watchNewPosts(),
      _onNewPost,
      isDisposed: () => _disposed,
      onError: (e) => dlog('[TimelineProvider] realtime error: $e'),
    );
  }

  /// Expose untuk test — memanggil jalur realtime tanpa Supabase.
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
      // Realtime posts TIDAK terfilter — update dari user mana pun (like,
      // view, komentar) memicu event ini. Kalau post ini TIDAK ada di feed
      // yang sedang dilihat, jangan notify (dulu notify global tiap update
      // → seluruh layar Timeline rebuild percuma).
      if (existingIdx < 0) return;
      final cur = _posts[existingIdx];
      final next = {
        ...cur,
        'likeCount': row['like_count'] ?? cur['likeCount'],
        'commentCount': row['comment_count'] ?? cur['commentCount'],
        'shareCount': row['share_count'] ?? cur['shareCount'],
        'isBoosted': row['is_boosted'] ?? cur['isBoosted'],
      };
      // Tidak ada perubahan nilai → jangan notify (hindari rebuild no-op).
      if (next['likeCount'] == cur['likeCount'] &&
          next['commentCount'] == cur['commentCount'] &&
          next['shareCount'] == cur['shareCount'] &&
          next['isBoosted'] == cur['isBoosted']) {
        return;
      }
      _posts[existingIdx] = next;
      _invalidateView();
      _syncScopeCache();
      if (!_disposed) notifyListeners();
      return;
    }
    if (_posts.any((p) => p['id'] == id)) return;
    final p = _mapRow(row);
    if (p == null) return;

    // Filter scope: post yang TIDAK visible di scope aktif tidak boleh
    // masuk feed (realtime mengirim SEMUA insert di tabel posts).
    final authorId = row['author_id'];
    final me = _sb.auth.currentUser?.id;
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
    if (!_disposed) notifyListeners();
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

  /// True bila cache komentar postId masih segar (< TTL) — pemanggil boleh
  /// tampilkan cache tanpa RPC.
  bool isCommentsFresh(String postId) {
    final at = _commentCacheAt[postId];
    if (at == null) return false;
    return DateTime.now().difference(at) < _commentTtl;
  }

  /// True bila ada cache (segar atau tidak) untuk postId.
  bool hasCommentsCache(String postId) => _commentCache.containsKey(postId);

  /// Simpan hasil fetch komentar ke cache.
  void cacheComments(String postId, List<Map<String, dynamic>> comments) {
    _commentCache[postId] = List.from(comments);
    _commentCacheAt[postId] = DateTime.now();
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

  /// Hapus komentar sendiri: server (RLS author-only) + cache + counter post.
  Future<void> deleteComment(String postId, int commentId) async {
    await _service.deleteComment(commentId);
    removeCommentFromCache(postId, commentId);
    final i = _posts.indexWhere((p) => p['id'] == postId);
    if (i >= 0) {
      final cur = ((_posts[i]['commentCount'] as num?)?.toInt() ?? 1);
      updatePost(postId, {'commentCount': (cur - 1).clamp(0, 1 << 31)});
    }
  }

  /// Hapus semua cache saat logout.
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

  // TTL cache followee — switch tab all⇄following bolak-balik tidak
  // mem-fetch daftar follows penuh berulang-ulang (query + network).
  DateTime? _followedIdsAt;
  static const _followedIdsTtl = Duration(seconds: 60);

  Future<void> _refreshFollowedIds({bool force = false}) async {
    if (!force &&
        _followedIdsAt != null &&
        DateTime.now().difference(_followedIdsAt!) < _followedIdsTtl) {
      return; // cache masih segar
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

  /// Set subscriber + blokir user aktif — dipakai filter realtime supaya
  /// post ber-visibilitas `subscribers`/`followers` dan post dari user yang
  /// di-blokir TIDAK bocor ke feed (SQL list_posts memfilter, realtime tidak).
  Future<void> _refreshVisibilitySets({bool force = false}) async {
    if (!force &&
        _visibilityAt != null &&
        DateTime.now().difference(_visibilityAt!) < _visibilityTtl) {
      return; // cache masih segar — jangan query tiap ganti tab
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
      if (!_disposed) notifyListeners();
    } catch (e) {
      dlog('[TimelineProvider] pricing error: $e');
    }
  }

  /// Prewarm SEMUA scope di background (dipanggil belakangan setelah app
  /// selesai warm-up) — saat user tap tab Timeline (termasuk Mengikuti &
  /// Postinganku) data sudah di memori, tidak ada spinner RPC pertama.
  /// Fetch scope non-aktif hanya mengisi cache — TIDAK menyentuh feed yang
  /// sedang dilihat user.
  Future<void> prewarm() async {
    if (_disposed) return;
    await Future.wait([
      for (final s in const ['all', 'following', 'mine'])
        if (_lastLoadedAt[s] == null) _fetchScope(s, refresh: true),
    ]);
  }

  /// Fetch satu scope dengan dedupe (klik tab / pull-refresh / pagination /
  /// prewarm tidak saling menimpa). Hasil di-apply ke feed tampilan HANYA
  /// bila scope tersebut masih tab aktif — sumber utama bug "Ketuk +"
  /// palsu & konten tab salah.
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

  /// Siapkan feed tampilan untuk scope: emit cache instan, atau bersihkan
  /// post tab lain + skeleton. Post tab lain TIDAK BOLEH terbawa ke tab
  /// baru (dulu jadi sumber konten salah & empty state palsu).
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
        DateTime.now().difference(_lastLoadedAt[scope]!) <
            const Duration(seconds: 30);
    if (fresh) {
      _posts
        ..clear()
        ..addAll(_excludeOwn(cached.posts, scope));
      _cursor = cached.cursor;
      _cursorBoosted = cached.cursorBoosted;
      _hasMore = cached.hasMore;
      _invalidateView();
      if (!_disposed) notifyListeners();
      return true;
    }
    if (cached != null && cached.posts.isNotEmpty) {
      // Frame pertama instant dari cache — server menyusul update fresh.
      _posts
        ..clear()
        ..addAll(_excludeOwn(cached.posts, scope));
      _cursor = cached.cursor;
      _cursorBoosted = cached.cursorBoosted;
      _hasMore = cached.hasMore;
      _invalidateView();
    } else {
      // Cache memori kosong — skeleton dulu, disk cache menyusul (async).
      _posts.clear();
      _invalidateView();
      _loadDiskScope(scope);
      _loading = true;
    }
    // Cache daftar followee/subscriber/blokir untuk filter realtime.
    if (scope == 'following') _refreshFollowedIds();
    if (scope == 'all') {
      _refreshFollowedIds();
      _refreshVisibilitySets();
    }
    if (!_disposed) notifyListeners();
    return false;
  }

  /// Scope 'following' tidak menampilkan post sendiri (ada tab Postinganku).
  /// Filter client untuk cache basi (memori/disk) — server (list_posts)
  /// sudah tidak mengirimnya lagi.
  List<Map<String, dynamic>> _excludeOwn(
      List<Map<String, dynamic>> posts, String scope) {
    if (scope != 'following') return posts;
    final me = _sb.auth.currentUser?.id;
    if (me == null) return posts;
    return posts.where((p) => '${p['authorId']}' != me).toList();
  }

  /// [skipIfFresh] dipakai saat GANTI TAB: bila cache scope masih segar
  /// (<30s) cukup tampilkan cache tanpa RPC. Refresh manual (pull) memakai
  /// `skipIfFresh: false` → selalu fetch.
  Future<void> load(
    String scope, {
    bool refresh = false,
    bool skipIfFresh = false,
  }) async {
    if (refresh) {
      final fresh = _prepareVisible(scope);
      if (skipIfFresh && fresh) return;
    }
    await _fetchScope(scope, refresh: refresh);
  }

  Future<void> _fetchScopeInner(String scope, {required bool refresh}) async {
    final active = _scope == scope;
    try {
      // Timeout: socket stall tidak boleh bikin spinner selamanya.
      // Nama metrik dibedakan refresh vs paginasi: refresh = fetch halaman
      // pertama (jalur yang menahan kemunculan tab Timeline), paginasi =
      // lanjutan saat scroll.
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
      if (_disposed) return;
      final list = _excludeOwn(fetched, scope);
      if (list.isEmpty) {
        if (active) _hasMore = false;
        if (refresh) {
          // Hapus feed HANYA bila server sukses menjawab kosong — network
          // error/timeout tidak boleh menghapus data lama (offline-safe).
          _scopeCache.remove(scope);
          if (active) {
            _posts.clear();
            _invalidateView();
          }
        }
      } else {
        final last = list.last;
        final lastCreated = last['createdAt'];
        // RPC list_posts mengembalikan createdAt sebagai String ISO-8601
        // (jsonb_build_object), BUKAN DateTime — parse dulu, kalau gagal
        // fallback now (halaman berikutnya tetap jalan, bukan stuck).
        final cursor = lastCreated is DateTime
            ? lastCreated
            : (DateTime.tryParse('$lastCreated') ?? DateTime.now());
        final boosted = last['isBoosted'] == true;
        final more = list.length >= 30;
        if (active) {
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
          // Cursor keyset konsisten dengan ORDER BY (is_boosted desc,
          // created_at desc).
          _cursor = cursor;
          _cursorBoosted = boosted;
          _hasMore = more;
          _invalidateView();
          _syncScopeCache();
          _prefetchComments();
        } else {
          // Scope bukan tab aktif (prewarm) — cukup isi cache, jangan
          // sentuh feed tampilan.
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
      // Tandai gagal — UI menampilkan retry, BUKAN empty state palsu.
      if (_scope == scope) {
        _lastFetchFailed = true;
        _scopeError = scope;
      }
      // _hasMore TIDAK diubah — pagination tetap bisa retry saat scroll
      // (error sementara bukan berarti ujung feed).
    } finally {
      if (_scope == scope) _loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Prefetch komentar post teratas yang ada komentarnya — sheet comment
  /// dibuka instan dari cache (jaringan tethering lambat). Fire-and-forget
  /// SETELAH jeda idle 500ms (supaya tidak bersaing dengan render feed +
  /// RPC halaman feed): kalau scope berganti / ada fetch baru, timer dibatal.
  /// Maks 2 post (dulu 5) — hemat kuota & tidak membanjiri koneksi.
  Timer? _prefetchTimer;
  void _prefetchComments() {
    if (_disposed) return;
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(milliseconds: 500), () {
      if (_disposed || _scope.isEmpty) return;
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
      if (_disposed) return;
      // Hanya isi bila masih kosong — jangan timpa optimistic user.
      if (!_commentCache.containsKey(postId)) {
        _commentCache[postId] = list;
        _commentCacheAt[postId] = DateTime.now();
      }
    } catch (_) {}
  }

  /// Update avatar di semua post milik uid — dipanggil setelah ganti foto
  /// supaya timeline langsung pakai foto baru tanpa pindah halaman.
  void refreshAvatarForUid(String uid, String newBase64) {
    if (uid.isEmpty) return;
    bool changed = false;
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
    // disk cache juga (next cold start pakai foto baru)
    _scheduleDiskSave();
    if (changed) {
      _invalidateView();
      if (!_disposed) notifyListeners();
    } else {
      // tidak ada post di cache tapi tetap notify biar _AuthorAvatar
      // rebuild dan ambil base64 baru dari AvatarB64Service cache
      if (!_disposed) notifyListeners();
    }
  }

  /// Mutasi lokal setelah aksi sukses (tanpa refetch penuh).
  void updatePost(String id, Map<String, dynamic> patch) {
    final i = _posts.indexWhere((p) => p['id'] == id);
    if (i >= 0) {
      _posts[i] = {..._posts[i], ...patch};
      _invalidateView();
      _syncScopeCache();
      if (!_disposed) notifyListeners();
    }
  }

  void removePost(String id) {
    _posts.removeWhere((p) => p['id'] == id);
    _invalidateView();
    _syncScopeCache();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _rtSub?.cancel();
    _authSub?.cancel();
    _prefetchTimer?.cancel();
    _diskSaveTimer?.cancel();
    super.dispose();
  }
}
