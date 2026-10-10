import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/cache/message_cache.dart';
import '../../services/rt_resilient.dart';
import '../../services/social_service.dart';
import '../../utils.dart';

/// State sosial user aktif (immutable).
class SocialState {
  final Set<String> following;
  final Set<String> friends;
  final Set<String> subscribed;
  final Set<String> pendingFriendRequests;
  final int friendRequestCount;

  bool isFollowing(String other) => following.contains(other);
  bool isFriend(String other) => friends.contains(other);
  bool isPendingFriendRequest(String other) =>
      pendingFriendRequests.contains(other);
  bool isSubscribed(String other) => subscribed.contains(other);

  const SocialState({
    this.following = const {},
    this.friends = const {},
    this.subscribed = const {},
    this.pendingFriendRequests = const {},
    this.friendRequestCount = 0,
  });

  @override
  bool operator ==(Object other) =>
      other is SocialState &&
      other.friendRequestCount == friendRequestCount &&
      setEquals(other.following, following) &&
      setEquals(other.friends, friends) &&
      setEquals(other.subscribed, subscribed) &&
      setEquals(other.pendingFriendRequests, pendingFriendRequests);

  @override
  int get hashCode => Object.hash(
        friendRequestCount,
        Object.hashAllUnordered(following),
        Object.hashAllUnordered(friends),
        Object.hashAllUnordered(subscribed),
        Object.hashAllUnordered(pendingFriendRequests),
      );
}

/// Provider sosial (Riverpod) — following/friends/subscribed/pending + aksi.
/// Migrasi dari ChangeNotifier (dengan realtime channel + auth sub +
/// debounce) → `Notifier`. Global (persist sepanjang sesi).
class SocialNotifier extends Notifier<SocialState> {
  final SocialService _service;
  final SupabaseClient _sb;

  SocialNotifier({SocialService? service, SupabaseClient? sb})
      : _sb = sb ?? Supabase.instance.client,
        _service = service ?? SocialService(sb ?? Supabase.instance.client);

  final Set<String> _following = {};
  final Set<String> _friends = {};
  final Set<String> _pendingFriendRequests = {};
  final Set<String> _subscribed = {};
  int _friendRequestCount = 0;

  /// Hook: dipanggil saat graf follow berubah (TimelineProvider pakai).
  void Function()? onFollowGraphChanged;

  StreamSubscription<int>? _frSub;
  StreamSubscription<AuthState>? _authSub;
  StreamSubscription? _rtSub;
  RealtimeChannel? _rtChannel;
  Timer? _refreshDebounce;

  @override
  SocialState build() {
    ref.onDispose(_disposeAll);
    unawaited(_loadDisk());
    _subscribe();
    _authSub = _sb.auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.signedIn ||
          s.event == AuthChangeEvent.signedOut ||
          s.event == AuthChangeEvent.initialSession) {
        _subscribe();
      }
    }, onError: (e) => dlog('[SocialProvider] auth stream error: $e'));
    return const SocialState();
  }

  void _emit() {
    state = SocialState(
      following: Set.unmodifiable(_following),
      friends: Set.unmodifiable(_friends),
      subscribed: Set.unmodifiable(_subscribed),
      pendingFriendRequests: Set.unmodifiable(_pendingFriendRequests),
      friendRequestCount: _friendRequestCount,
    );
  }

  Future<void> _loadDisk() async {
    try {
      final rows = await MessageCache.instance.loadRawList('social_sets');
      if (rows.isEmpty) return;
      final obj = rows.first;
      if (_friends.isNotEmpty) return;
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
      _emit();
    } catch (_) {}
  }

  Future<void> clearAnonSocial() async {
    try {
      await _service.clearAnonSocial();
      _following.clear();
      _friends.clear();
      _pendingFriendRequests.clear();
      _subscribed.clear();
      _friendRequestCount = 0;
      _emit();
    } catch (e) {
      dlog('[SocialProvider] clearAnonSocial error: $e');
    }
  }

  void _listenRealtime() {
    _rtSub?.cancel();
    final uid = _service.uid;
    if (uid == null) return;
    final channel = _sb.channel('social-rt-$uid');
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
        .subscribe((status, err) {
          if (err != null) dlog('[SocialProvider] realtime error: $err');
        });
    _rtChannel = channel;
  }

  void _subscribe() {
    _frSub?.cancel();
    final uid = _service.uid;
    if (uid == null) {
      _following.clear();
      _friends.clear();
      _pendingFriendRequests.clear();
      _subscribed.clear();
      _friendRequestCount = 0;
      _emit();
      return;
    }
    _listenRealtime();
    _frSub?.cancel();
    _frSub = listenResilient<int>(
      () => _service.watchFriendRequestCount(uid),
      (count) {
        if (_friendRequestCount != count) {
          _friendRequestCount = count;
          _emit();
        }
      },
      isDisposed: () => false,
      onError: (e) => dlog('[SocialProvider] fr-count stream error: $e'),
    );
    _refreshSelfSetsNow();
  }

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
      final pending = <String>{
        for (final e in (results[3] as List))
          if (e['status'] == null || e['status'] == 'pending') '${e['uid']}',
        for (final e in (results[4] as List))
          if (e['status'] == null || e['status'] == 'pending')
            '${e['uid'] ?? e['from_id']}',
      };
      _pendingFriendRequests
        ..clear()
        ..addAll(pending);
      _friendRequestCount = (results[4] as List).length;
      _emit();
      unawaited(MessageCache.instance.saveRawList('social_sets', [
        {
          'following': _following.toList(),
          'friends': _friends.toList(),
          'pending': _pendingFriendRequests.toList(),
          'subscribed': _subscribed.toList(),
        }
      ]));
    } catch (e) {
      dlog('[SocialProvider] refreshSelfSets error: $e');
    }
  }

  // ── Passthrough ──
  String? get uid => _service.uid;
  // Helper status (agar konsumen tak perlu ubah pola `sp.isFriend(x)`).
  bool isFollowing(String other) => _following.contains(other);
  bool isFriend(String other) => _friends.contains(other);
  bool isPendingFriendRequest(String other) =>
      _pendingFriendRequests.contains(other);
  bool isSubscribed(String other) => _subscribed.contains(other);
  Set<String> get friends => Set.unmodifiable(_friends);
  Set<String> get following => Set.unmodifiable(_following);
  Set<String> get subscribed => Set.unmodifiable(_subscribed);
  Set<String> get pendingFriendRequests =>
      Set.unmodifiable(_pendingFriendRequests);
  int get friendRequestCount => _friendRequestCount;
  Future<Map<String, dynamic>> mySocialStatus(String otherUid,
          {bool force = false}) =>
      _service.mySocialStatus(otherUid, force: force);
  Future<List<Map<String, dynamic>>> socialList(String kind, String uid,
          {int limit = 50, int offset = 0}) =>
      _service.socialList(kind, uid, limit: limit, offset: offset);
  Future<Map<String, dynamic>> unsubscribeCreator(String uid) =>
      _service.unsubscribeCreator(uid);

  Future<Map<String, dynamic>> respondFriendRequest(int id, bool accept) async {
    final res = await _service.respondFriendRequest(id, accept);
    _service.invalidateSocialStatus();
    try {
      if (accept) {
        await _refreshSelfSetsNow();
      } else {
        final inbox = await _service.friendRequestInbox();
        _friendRequestCount = inbox.length;
      }
    } catch (_) {}
    _emit();
    return res;
  }

  Future<bool> cancelFriendRequest(int id, {String targetUid = ''}) async {
    try {
      final res = await _service.cancelFriendRequest(id);
      if (res['ok'] == true) {
        _service.invalidateSocialStatus(targetUid.isNotEmpty ? targetUid : null);
        if (targetUid.isNotEmpty) _pendingFriendRequests.remove(targetUid);
        _emit();
        return true;
      }
      return false;
    } catch (e) {
      dlog('[SocialProvider] cancelFriendRequest error: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> friendRequestInbox(
          {int limit = 50, int offset = 0}) =>
      _service.friendRequestInbox(limit: limit, offset: offset);
  Future<List<Map<String, dynamic>>> friendRequestOutbox(
          {int limit = 50, int offset = 0}) =>
      _service.friendRequestOutbox(limit: limit, offset: offset);
  Future<List<Map<String, dynamic>>> mySubscriptions() =>
      _service.mySubscriptions();

  Future<bool> follow(String targetUid) async {
    try {
      final res = await _service.followUser(targetUid);
      if (res['ok'] == true) {
        _service.invalidateSocialStatus(targetUid);
        _following.add(targetUid);
        onFollowGraphChanged?.call();
        _emit();
        return true;
      }
      return false;
    } catch (e) {
      dlog('[SocialProvider] follow error: $e');
      return false;
    }
  }

  Future<bool> unfollow(String targetUid) async {
    try {
      final res = await _service.unfollowUser(targetUid);
      if (res['ok'] == true) {
        _service.invalidateSocialStatus(targetUid);
        _following.remove(targetUid);
        _friends.remove(targetUid);
        onFollowGraphChanged?.call();
        _emit();
        return true;
      }
      return false;
    } catch (e) {
      dlog('[SocialProvider] unfollow error: $e');
      return false;
    }
  }

  Future<String> sendFriendRequest(String targetUid) async {
    if (targetUid.isEmpty) return 'failed';
    try {
      final res = await _service.sendFriendRequest(targetUid);
      if (res['already_friends'] == true) {
        _service.invalidateSocialStatus(targetUid);
        _friends.add(targetUid);
        _pendingFriendRequests.remove(targetUid);
        _emit();
        return 'friends';
      }
      if (res['ok'] == true) {
        _service.invalidateSocialStatus(targetUid);
        _pendingFriendRequests.add(targetUid);
        _emit();
        return 'pending';
      }
      return 'failed';
    } catch (e) {
      dlog('[SocialProvider] sendFriendRequest error: $e');
      return 'failed';
    }
  }

  Future<void> refreshInbox() async {
    final uid = _service.uid;
    if (uid == null) return;
    try {
      final inbox = await _service.friendRequestInbox();
      _friendRequestCount = inbox.length;
      _emit();
    } catch (e) {
      dlog('[SocialProvider] refreshInbox error: $e');
    }
  }

  Future<Map<String, dynamic>> subscribe(String creatorUid,
          {int periods = 1}) async {
    final res = await _service.subscribeCreator(creatorUid, periods: periods);
    _service.invalidateSubscriptions();
    _service.invalidateSocialStatus(creatorUid);
    _subscribed.add(creatorUid);
    _emit();
    return res;
  }

  Future<void> unsubscribe(String creatorUid) async {
    await _service.unsubscribeCreator(creatorUid);
    _service.invalidateSubscriptions();
    _service.invalidateSocialStatus(creatorUid);
    _subscribed.remove(creatorUid);
    _emit();
  }

  Future<bool> setSubscriptionPrice(int price) async {
    try {
      await _service.setSubscriptionPrice(price);
      return true;
    } catch (e) {
      dlog('[SocialProvider] setSubscriptionPrice error: $e');
      return false;
    }
  }

  void _disposeAll() {
    _refreshDebounce?.cancel();
    _frSub?.cancel();
    _authSub?.cancel();
    _rtSub?.cancel();
    final ch = _rtChannel;
    _rtChannel = null;
    if (ch != null) _sb.removeChannel(ch);
  }
}

final socialProvider =
    NotifierProvider<SocialNotifier, SocialState>(SocialNotifier.new);
