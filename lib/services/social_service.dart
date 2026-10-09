import 'dart:async';
import '../utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'subscription_rpc.dart';
import '../core/perf/rpc_probe.dart';

/// Service untuk social graph: follow, friend request, subscribe.
class SocialService {
  final SupabaseClient _sb;
  SocialService([SupabaseClient? sb]) : _sb = sb ?? Supabase.instance.client;

  String? get uid => _sb.auth.currentUser?.id;

  /// Dedupe RPC read idempoten (in-flight coalescing) — boot menembak
  /// social_list ×4, inbox/outbox ×2, subscriptions ×2 bersamaan. Cukup 1
  /// RPC per key dalam satu window singkat; sisanya menunggu future sama.
  final Map<String, Future<Object?>> _inflight = {};

  // ── TTL cache my_social_status per-uid (jarang berubah: hanya saat
  // follow/unfollow/friend/block). Buka profil orang berulang tak perlu RPC
  // tiap kali. `invalidateSocialStatus` dipanggil saat aksi sosial.
  static const Duration _socialStatusTtl = Duration(seconds: 60);
  final Map<String, ({Map<String, dynamic> val, DateTime at})>
      _socialStatusCache = {};

  void invalidateSocialStatus([String? uid]) {
    if (uid == null) {
      _socialStatusCache.clear();
    } else {
      _socialStatusCache.remove(uid);
    }
  }

  // ── TTL cache my_subscriptions (jarang berubah: hanya saat subscribe/
  // unsubscribe). Buka layar Langganan berulang tak RPC tiap kali.
  static const Duration _subsTtl = Duration(seconds: 30);
  ({List<Map<String, dynamic>> val, DateTime at})? _subsCache;
  void invalidateSubscriptions() => _subsCache = null;
  Future<T> _coalesce<T>(String key, Future<T> Function() fn) {
    final running = _inflight[key];
    if (running != null) return running.then((v) => v as T);
    final fut = fn();
    _inflight[key] = fut;
    fut.whenComplete(() {
      if (identical(_inflight[key], fut)) _inflight.remove(key);
    });
    return fut;
  }

  /// Jumlah teman & follower (bulk) untuk daftar uid — dipakai badge
  /// "1.2K Followers · 34 Friends" di kartu (gaya IG). Return map
  /// uid → {friends, followers}. Kosong bila gagal / uid kosong.
  Future<Map<String, ({int friends, int followers})>> countsForUids(
    List<String> uids,
  ) async {
    if (uids.isEmpty) return const {};
    try {
      final res = await measuredRpc(
        _sb,
        'social_counts_uids',
        params: {'p_uids': uids},
      );
      if (res is Map) {
        final out = <String, ({int friends, int followers})>{};
        for (final e in res.entries) {
          final v = e.value;
          if (v is Map) {
            out['${e.key}'] = (
              friends: (v['friends'] as num?)?.toInt() ?? 0,
              followers: (v['followers'] as num?)?.toInt() ?? 0,
            );
          }
        }
        return out;
      }
    } catch (e) {
      dlog('[SocialService] countsForUids error: $e');
    }
    return const {};
  }

  Future<Map<String, dynamic>> followUser(String targetUid) async {
    final res = await measuredRpc(_sb, 'follow_user', params: {'p_followee': targetUid});
    return _map(res);
  }

  Future<Map<String, dynamic>> unfollowUser(String targetUid) async {
    final res = await measuredRpc(_sb, 
      'unfollow_user',
      params: {'p_followee': targetUid},
    );
    return _map(res);
  }

  Future<Map<String, dynamic>> sendFriendRequest(String targetUid) async {
    final res = await measuredRpc(_sb, 
      'send_friend_request',
      params: {'p_to': targetUid},
    );
    return _map(res);
  }

  Future<Map<String, dynamic>> respondFriendRequest(
    int requestId,
    bool accept,
  ) async {
    final res = await measuredRpc(_sb, 
      'respond_friend_request',
      params: {'p_request_id': requestId, 'p_accept': accept},
    );
    return _map(res);
  }

  /// Batalkan friend request yang SUDAH dikirim (hanya pengirim).
  Future<Map<String, dynamic>> cancelFriendRequest(int requestId) async {
    final res = await measuredRpc(_sb, 
      'cancel_friend_request',
      params: {'p_request_id': requestId},
    );
    return _map(res);
  }

  Future<Map<String, dynamic>> subscribeCreator(
    String creatorUid, {
    int periods = 1,
  }) async {
    final r = await subscribeCreatorRpc(_sb, creatorUid, periods: periods);
    invalidateSubscriptions();
    invalidateSocialStatus(creatorUid);
    return r;
  }

  Future<Map<String, dynamic>> unsubscribeCreator(String creatorUid) async {
    final res = await measuredRpc(_sb, 
      'unsubscribe_creator',
      params: {'p_creator': creatorUid},
    );
    invalidateSubscriptions();
    invalidateSocialStatus(creatorUid);
    return _map(res);
  }

  Future<Map<String, dynamic>> setSubscriptionPrice(int price) async {
    final res = await measuredRpc(_sb, 
      'set_subscription_price',
      params: {'p_price': price},
    );
    return _map(res);
  }

  Future<Map<String, dynamic>> mySocialStatus(
    String otherUid, {
    bool force = false,
  }) async {
    // PERF: TTL cache per-uid — buka profil orang berulang tak RPC tiap kali.
    final cached = _socialStatusCache[otherUid];
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.at) < _socialStatusTtl) {
      return cached.val;
    }
    final res = await measuredRpc(_sb, 
      'my_social_status',
      params: {'p_other': otherUid},
    );
    final val = _map(res);
    _socialStatusCache[otherUid] = (val: val, at: DateTime.now());
    return val;
  }

  Future<List<Map<String, dynamic>>> socialList(
    String kind,
    String userUid, {
    int limit = 50,
  }) {
    return _coalesce<List<Map<String, dynamic>>>(
      'social_list:$kind:$userUid',
      () async {
        try {
          final res = await measuredRpc(_sb, 
            'social_list',
            params: {'p_kind': kind, 'p_user': userUid, 'p_limit': limit},
          );
          return _list(res);
        } catch (e) {
          dlog('[SocialService] socialList error: $e');
          return [];
        }
      },
    );
  }

  Future<List<Map<String, dynamic>>> friendRequestInbox({
    int limit = 50,
    int offset = 0,
  }) {
    return _coalesce<List<Map<String, dynamic>>>(
      'fr_inbox:$limit:$offset',
      () async {
        try {
          final res = await measuredRpc(_sb, 
            'friend_request_inbox_page',
            params: {'p_limit': limit, 'p_offset': offset},
          );
          return _list(res);
        } catch (e) {
          dlog('[SocialService] inbox error: $e');
          return [];
        }
      },
    );
  }

  Future<List<Map<String, dynamic>>> friendRequestOutbox({
    int limit = 50,
    int offset = 0,
  }) {
    return _coalesce<List<Map<String, dynamic>>>(
      'fr_outbox:$limit:$offset',
      () async {
        try {
          final res = await measuredRpc(_sb, 
            'friend_request_outbox_page',
            params: {'p_limit': limit, 'p_offset': offset},
          );
          return _list(res);
        } catch (e) {
          dlog('[SocialService] outbox error: $e');
          return [];
        }
      },
    );
  }

  Future<List<Map<String, dynamic>>> mySubscriptions() {
    // TTL 30s — buka layar Langganan berulang tak RPC tiap kali.
    final c = _subsCache;
    if (c != null && DateTime.now().difference(c.at) < _subsTtl) {
      return Future.value(c.val);
    }
    return _coalesce<List<Map<String, dynamic>>>('my_subscriptions', () async {
      try {
        final res = await measuredRpc(_sb, 'my_subscriptions');
        final v = _list(res);
        _subsCache = (val: v, at: DateTime.now());
        return v;
      } catch (e) {
        dlog('[SocialService] mySubscriptions error: $e');
        return [];
      }
    });
  }

  /// Hapus semua relasi sosial (follow, subscribe, friend request) milik
  /// user anon — dipanggil saat anon logout supaya counter user lain
  /// (followers/subscribers) ikut berkurang via trigger.
  /// Hapus relasi sosial akun anon saat logout.
  ///
  /// WAJIB pakai timeout: RPC jaringan tanpa batas waktu membuat spinner
  /// logout muter selamanya saat jaringan lambat/menggantung — user tidak
  /// pernah sampai ke layar login. Kegagalan aman diabaikan (relasi sosial
  /// anon boleh tersisa; yang penting user bisa keluar).
  Future<void> clearAnonSocial() async {
    try {
      await _sb
          .rpc('clear_anon_social')
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      dlog('[SocialService] clearAnonSocial error: $e');
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
