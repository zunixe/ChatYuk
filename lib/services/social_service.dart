import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service untuk social graph: follow, friend request, subscribe.
class SocialService {
  final SupabaseClient _sb;
  SocialService([SupabaseClient? sb]) : _sb = sb ?? Supabase.instance.client;

  String? get uid => _sb.auth.currentUser?.id;

  Future<Map<String, dynamic>> followUser(String targetUid) async {
    final res = await _sb.rpc('follow_user', params: {'p_followee': targetUid});
    return _map(res);
  }

  Future<Map<String, dynamic>> unfollowUser(String targetUid) async {
    final res = await _sb.rpc(
      'unfollow_user',
      params: {'p_followee': targetUid},
    );
    return _map(res);
  }

  Future<Map<String, dynamic>> sendFriendRequest(String targetUid) async {
    final res = await _sb.rpc(
      'send_friend_request',
      params: {'p_to': targetUid},
    );
    return _map(res);
  }

  Future<Map<String, dynamic>> respondFriendRequest(
    int requestId,
    bool accept,
  ) async {
    final res = await _sb.rpc(
      'respond_friend_request',
      params: {'p_request_id': requestId, 'p_accept': accept},
    );
    return _map(res);
  }

  Future<Map<String, dynamic>> subscribeCreator(
    String creatorUid, {
    int periods = 1,
  }) async {
    final res = await _sb.rpc(
      'subscribe_creator',
      params: {'p_creator': creatorUid, 'p_periods': periods},
    );
    return _map(res);
  }

  Future<Map<String, dynamic>> unsubscribeCreator(String creatorUid) async {
    final res = await _sb.rpc(
      'unsubscribe_creator',
      params: {'p_creator': creatorUid},
    );
    return _map(res);
  }

  Future<Map<String, dynamic>> setSubscriptionPrice(int price) async {
    final res = await _sb.rpc(
      'set_subscription_price',
      params: {'p_price': price},
    );
    return _map(res);
  }

  Future<Map<String, dynamic>> mySocialStatus(String otherUid) async {
    final res = await _sb.rpc(
      'my_social_status',
      params: {'p_other': otherUid},
    );
    return _map(res);
  }

  Future<List<Map<String, dynamic>>> socialList(
    String kind,
    String userUid, {
    int limit = 50,
  }) async {
    try {
      final res = await _sb.rpc(
        'social_list',
        params: {'p_kind': kind, 'p_user': userUid, 'p_limit': limit},
      );
      return _list(res);
    } catch (e) {
      debugPrint('[SocialService] socialList error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> friendRequestInbox() async {
    try {
      final res = await _sb.rpc('friend_request_inbox');
      return _list(res);
    } catch (e) {
      debugPrint('[SocialService] inbox error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> friendRequestOutbox() async {
    try {
      final res = await _sb.rpc('friend_request_outbox');
      return _list(res);
    } catch (e) {
      debugPrint('[SocialService] outbox error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> mySubscriptions() async {
    try {
      final res = await _sb.rpc('my_subscriptions');
      return _list(res);
    } catch (e) {
      debugPrint('[SocialService] mySubscriptions error: $e');
      return [];
    }
  }

  /// Hapus semua relasi sosial (follow, subscribe, friend request) milik
  /// user anon — dipanggil saat anon logout supaya counter user lain
  /// (followers/subscribers) ikut berkurang via trigger.
  Future<void> clearAnonSocial() async {
    try {
      await _sb.rpc('clear_anon_social');
    } catch (e) {
      debugPrint('[SocialService] clearAnonSocial error: $e');
    }
  }

  /// Realtime friend request inbox (pending) untuk badge unread.
  Stream<int> watchFriendRequestCount(String uid) {
    if (uid.isEmpty) return const Stream.empty();
    return _sb.from('friend_requests').stream(primaryKey: ['id']).map((rows) {
      return rows
          .where((r) => r['to_id'] == uid && r['status'] == 'pending')
          .length;
    });
  }

  Map<String, dynamic> _map(dynamic res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    return {};
  }

  List<Map<String, dynamic>> _list(dynamic res) {
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [];
  }
}
