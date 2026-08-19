import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/timeline_service.dart';

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
    // Supabase signOut men-teardown semua channel realtime — subscribe
    // ulang saat user baru login supaya live-update timeline tetap jalan.
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn) {
        _listenRealtime();
        _refreshVisibilitySets();
      }
    });
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

  Future<void> refreshPricing() async {    try {
      final p = await _service.pricing();
      _boostPaid = (p['boost_paid'] as num?)?.toInt() ?? _boostPaid;
      _boostBonus = (p['boost_bonus'] as num?)?.toInt() ?? _boostBonus;
      _postsDailyLimit = (p['posts_daily_limit'] as num?)?.toInt() ?? _postsDailyLimit;
      notifyListeners();
    } catch (e) {
      debugPrint('[TimelineProvider] pricing error: $e');
    }
  }

  Future<void> load(String scope, {bool refresh = false}) async {
    if (_loading) return;
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
      // Refresh APA PUN (tab switch, pull-to-refresh, habis posting): JANGAN
      // clear dulu — konten lama tetap tampil selama fetch, lalu diganti
      // atomically. List hanya dikosongkan kalau hasil fetch memang kosong
      // (di bawah), supaya tidak pernah blink ke empty state saat data ada.
    }
    _loading = true;
    notifyListeners();
    try {
      final list = await _service.listPosts(
        scope,
        cursor: _cursor,
        cursorBoosted: _cursorBoosted,
      );
      if (list.isEmpty) {
        _hasMore = false;
        if (refresh) {
          _posts.clear();
          _invalidateView();
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
      notifyListeners();
    }
  }

  void removePost(String id) {
    _posts.removeWhere((p) => p['id'] == id);
    _invalidateView();
    notifyListeners();
  }

  @override
  void dispose() {
    _rtSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }
}