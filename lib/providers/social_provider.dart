import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/social_service.dart';
import '../services/message_cache.dart';

/// State sosial user aktif: following set, friend request inbox count,
/// dan helper aksi follow/friend/subscribe.
class SocialProvider extends ChangeNotifier {
  bool _disposed = false;

  final SocialService _service = SocialService(Supabase.instance.client);

  final Set<String> _following = {};
  final Set<String> _friends = {};
  // UID lawan yang punya friend request pending (SENT oleh saya ATAU
  // RECEIVED dari dia) — dipakai tombol "Tambah Teman" di list chat agar
  // render final TANPA RPC per-item (dulu: N RPC my_social_status →
  // spinner berjejak saat jaringan lambat).
  final Set<String> _pendingFriendRequests = {};
  final Set<String> _subscribed = {};
  int _friendRequestCount = 0;

  StreamSubscription<int>? _frSub;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription? _rtSub;
  RealtimeChannel? _rtChannel;
  Timer? _refreshDebounce;

  Set<String> get following => Set.unmodifiable(_following);
  Set<String> get friends => Set.unmodifiable(_friends);
  Set<String> get subscribed => Set.unmodifiable(_subscribed);
  Set<String> get pendingFriendRequests =>
      Set.unmodifiable(_pendingFriendRequests);
  int get friendRequestCount => _friendRequestCount;

  bool isFollowing(String uid) => _following.contains(uid);
  bool isFriend(String uid) => _friends.contains(uid);
  bool isPendingFriendRequest(String uid) =>
      _pendingFriendRequests.contains(uid);
  bool isSubscribed(String uid) => _subscribed.contains(uid);

  SocialProvider() {
    // Warm-up dari disk cache — status teman/pending tampil instan saat
    // cold start (network refresh menyusul, tanpa spinner di UI).
    unawaited(_loadDisk());
    _subscribe();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.signedOut ||
          state.event == AuthChangeEvent.initialSession) {
        _subscribe();
      }
    });
  }

  /// Muat set sosial dari disk cache (instant, sebelum network refresh).
  Future<void> _loadDisk() async {
    try {
      final rows = await MessageCache.instance.loadRawList('social_sets');
      if (rows.isEmpty) return;
      final obj = rows.first;
      if (_friends.isNotEmpty) return; // server sudah lebih dulu
      _following
        ..clear()
        ..addAll((obj['following'] as List?)?.map((e) => '$e') ?? const []);
      _friends
        ..clear()
        ..addAll((obj['friends'] as List?)?.map((e) => '$e') ?? const []);
      _pendingFriendRequests
        ..clear()
        ..addAll((obj['pending'] as List?)?.map((e) => '$e') ?? const []);
      _subscribed
        ..clear()
        ..addAll((obj['subscribed'] as List?)?.map((e) => '$e') ?? const []);
      if (!_disposed) notifyListeners();
    } catch (_) {}
  }

  /// Bersihkan relasi sosial anon (follow/subscribe/friend request) di
  /// server lalu state lokal — dipanggil sebelum anon signOut.
  Future<void> clearAnonSocial() async {
    try {
      await _service.clearAnonSocial();
      _following.clear();
      _friends.clear();
      _pendingFriendRequests.clear();
      _subscribed.clear();
      _friendRequestCount = 0;
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('[SocialProvider] clearAnonSocial error: $e');
    }
  }

  /// Realtime: setiap perubahan follows/friend_requests yang melibatkan uid
  /// sendiri → refresh set (following/friends) + counter di profil ikut
  /// ter-update lewat AuthProvider.onMyProfileUpdates (profiles realtime).
  void _listenRealtime() {
    _rtSub?.cancel();
    final uid = _service.uid;
    if (uid == null) return;
    final sb = Supabase.instance.client;
    final channel = sb.channel('social-rt-$uid');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'follows',
          callback: (payload) => _refreshSelfSets(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'friend_requests',
          callback: (payload) => _refreshSelfSets(),
        )
        .subscribe();
    _rtChannel = channel;
  }

  void _subscribe() {
    _frSub?.cancel();
    final uid = _service.uid;
    if (uid == null) {
      // Logout: bersihkan state akun lama supaya tidak bocor ke akun baru.
      _following.clear();
      _friends.clear();
      _pendingFriendRequests.clear();
      _subscribed.clear();
      _friendRequestCount = 0;
      if (!_disposed) notifyListeners();
      return;
    }
    // Realtime channel dibuat ulang di sini (bukan hanya constructor) —
    // setelah logout, removeAllChannels men-teardown channel lama, jadi
    // login berikutnya harus membuat channel baru dengan uid yang baru.
    _listenRealtime();
    _frSub = _service.watchFriendRequestCount(uid).listen((count) {
      if (_friendRequestCount != count) {
        _friendRequestCount = count;
        if (!_disposed) notifyListeners();
      }
    });
    // Muat set awal (following/friends/subscribed) untuk uid sendiri.
    _refreshSelfSetsNow();
  }

  /// Coalesce burst event realtime (follow/unfollow beruntun) jadi satu
  /// refresh — tiap event = 3 query, debounce 400ms mencegah storm RPC.
  Future<void> _refreshSelfSets() async {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(
      const Duration(milliseconds: 400),
      _refreshSelfSetsNow,
    );
  }

  Future<void> _refreshSelfSetsNow() async {
    final uid = _service.uid;
    if (uid == null) return;
    try {
      // Tiga fetch paralel + outbox/inbox (pending friend request) —
      // dulu berurutan; paralel memangkas waktu sinkron di jaringan lambat.
      final results = await Future.wait([
        _service.socialList('following', uid),
        _service.socialList('friends', uid),
        _service.mySubscriptions(),
        _service.friendRequestOutbox(),
        _service.friendRequestInbox(),
      ]);
      _following
        ..clear()
        ..addAll((results[0] as List).map((e) => '${e['uid']}'));
      _friends
        ..clear()
        ..addAll((results[1] as List).map((e) => '${e['uid']}'));
      _subscribed
        ..clear()
        ..addAll((results[2] as List).map((e) => '${e['uid']}'));
      // Pending = SENT (outbox) + RECEIVED (inbox) yang masih pending.
      final pending = <String>{
        for (final e in (results[3] as List))
          if (e['status'] == null ||
              e['status'] == 'pending') '${e['uid']}',
        for (final e in (results[4] as List))
          if (e['status'] == null ||
              e['status'] == 'pending') '${e['uid'] ?? e['from_id']}',
      };
      _pendingFriendRequests
        ..clear()
        ..addAll(pending);
      if (!_disposed) notifyListeners();
      // Cache disk — buka app berikutnya status teman tampil instan.
      unawaited(MessageCache.instance.saveRawList('social_sets', [
        {
          'following': _following.toList(),
          'friends': _friends.toList(),
          'pending': _pendingFriendRequests.toList(),
          'subscribed': _subscribed.toList(),
        }
      ]));
    } catch (e) {
      debugPrint('[SocialProvider] refreshSelfSets error: $e');
    }
  }

  Future<bool> follow(String targetUid) async {
    try {
      final res = await _service.followUser(targetUid);
      if (res['ok'] == true) {
        _following.add(targetUid);
        if (!_disposed) notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[SocialProvider] follow error: $e');
      return false;
    }
  }

  Future<bool> unfollow(String targetUid) async {
    try {
      final res = await _service.unfollowUser(targetUid);
      if (res['ok'] == true) {
        _following.remove(targetUid);
        _friends.remove(targetUid);
        if (!_disposed) notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[SocialProvider] unfollow error: $e');
      return false;
    }
  }

  Future<String> sendFriendRequest(String targetUid) async {
    try {
      final res = await _service.sendFriendRequest(targetUid);
      if (res['already_friends'] == true) {
        _friends.add(targetUid);
        _pendingFriendRequests.remove(targetUid);
      } else {
        // Optimistic: tombol langsung jadi "Requested" tanpa spinner.
        _pendingFriendRequests.add(targetUid);
      }
      if (!_disposed) notifyListeners();
      return res['status']?.toString() ?? '';
    } catch (e) {
      debugPrint('[SocialProvider] sendFriendRequest error: $e');
      return '';
    }
  }

  Future<void> refreshInbox() async {
    final uid = _service.uid;
    if (uid == null) return;
    try {
      final inbox = await _service.friendRequestInbox();
      _friendRequestCount = inbox.length;
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('[SocialProvider] refreshInbox error: $e');
    }
  }

  Future<Map<String, dynamic>> subscribe(
    String creatorUid, {
    int periods = 1,
  }) async {
    try {
      final res = await _service.subscribeCreator(creatorUid, periods: periods);
      if (res['ok'] == true) {
        _subscribed.add(creatorUid);
        if (!_disposed) notifyListeners();
      }
      return res;
    } catch (e) {
      debugPrint('[SocialProvider] subscribe error: $e');
      rethrow;
    }
  }

  Future<void> unsubscribe(String creatorUid) async {
    await _service.unsubscribeCreator(creatorUid);
    _subscribed.remove(creatorUid);
    if (!_disposed) notifyListeners();
  }

  Future<bool> setSubscriptionPrice(int price) async {
    try {
      final res = await _service.setSubscriptionPrice(price);
      return res['ok'] == true;
    } catch (e) {
      debugPrint('[SocialProvider] setSubscriptionPrice error: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshDebounce?.cancel();
    _frSub?.cancel();
    _authSub?.cancel();
    _rtSub?.cancel();
    final ch = _rtChannel;
    if (ch != null) Supabase.instance.client.removeChannel(ch);
    super.dispose();
  }
}
