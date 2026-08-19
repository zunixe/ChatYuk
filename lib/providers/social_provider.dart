import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/social_service.dart';

/// State sosial user aktif: following set, friend request inbox count,
/// dan helper aksi follow/friend/subscribe.
class SocialProvider extends ChangeNotifier {
  final SocialService _service = SocialService(Supabase.instance.client);

  final Set<String> _following = {};
  final Set<String> _friends = {};
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
  int get friendRequestCount => _friendRequestCount;

  bool isFollowing(String uid) => _following.contains(uid);
  bool isFriend(String uid) => _friends.contains(uid);
  bool isSubscribed(String uid) => _subscribed.contains(uid);

  SocialProvider() {
    _subscribe();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.signedIn ||
          state.event == AuthChangeEvent.signedOut ||
          state.event == AuthChangeEvent.initialSession) {
        _subscribe();
      }
    });
  }

  /// Bersihkan relasi sosial anon (follow/subscribe/friend request) di
  /// server lalu state lokal — dipanggil sebelum anon signOut.
  Future<void> clearAnonSocial() async {
    try {
      await _service.clearAnonSocial();
      _following.clear();
      _friends.clear();
      _subscribed.clear();
      _friendRequestCount = 0;
      notifyListeners();
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
      _subscribed.clear();
      _friendRequestCount = 0;
      notifyListeners();
      return;
    }
    // Realtime channel dibuat ulang di sini (bukan hanya constructor) —
    // setelah logout, removeAllChannels men-teardown channel lama, jadi
    // login berikutnya harus membuat channel baru dengan uid yang baru.
    _listenRealtime();
    _frSub = _service.watchFriendRequestCount(uid).listen((count) {
      if (_friendRequestCount != count) {
        _friendRequestCount = count;
        notifyListeners();
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
      final following = await _service.socialList('following', uid);
      final friends = await _service.socialList('friends', uid);
      final subs = await _service.mySubscriptions();
      _following
        ..clear()
        ..addAll(following.map((e) => '${e['uid']}'));
      _friends
        ..clear()
        ..addAll(friends.map((e) => '${e['uid']}'));
      _subscribed
        ..clear()
        ..addAll(subs.map((e) => '${e['uid']}'));
      notifyListeners();
    } catch (e) {
      debugPrint('[SocialProvider] refreshSelfSets error: $e');
    }
  }

  Future<bool> follow(String targetUid) async {
    try {
      final res = await _service.followUser(targetUid);
      if (res['ok'] == true) {
        _following.add(targetUid);
        notifyListeners();
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
        notifyListeners();
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
      if (res['already_friends'] == true) return 'friends';
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
      notifyListeners();
    } catch (e) {
      debugPrint('[SocialProvider] refreshInbox error: $e');
    }
  }

  Future<Map<String, dynamic>> subscribe(String creatorUid, {int periods = 1}) async {
    try {
      final res = await _service.subscribeCreator(creatorUid, periods: periods);
      if (res['ok'] == true) {
        _subscribed.add(creatorUid);
        notifyListeners();
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
    notifyListeners();
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
    _refreshDebounce?.cancel();
    _frSub?.cancel();
    _authSub?.cancel();
    _rtSub?.cancel();
    final ch = _rtChannel;
    if (ch != null) Supabase.instance.client.removeChannel(ch);
    super.dispose();
  }
}
