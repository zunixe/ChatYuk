import 'dart:async';
import '../utils.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'subscription_rpc.dart';
import '../core/perf/rpc_probe.dart';

class PointsService {
  final SupabaseClient _sb;

  PointsService([SupabaseClient? sb]) : _sb = sb ?? Supabase.instance.client;

  Future<bool> fetchEnabled() async {
    final res = await measuredRpc(_sb, 'get_points_enabled');
    return res == true;
  }

  /// Harga fitur berbayar (call per menit, filter, nearby) untuk UI.
  Future<Map<String, dynamic>> meteredPricing() async {
    try {
      final res = await measuredRpc(_sb, 'metered_pricing_public');
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      dlog('[PointsService] meteredPricing error: $e');
    }
    return {
      'call_audio_cost_per_min': 6,
      'call_video_cost_per_min': 20,
      'call_free_minutes_daily': 5,
      'filter_gender_cost': 15,
      'nearby_cost': 25,
    };
  }

  /// Feature flags (published per fitur) untuk gate UI.
  Future<Map<String, dynamic>> featureFlags() async {
    try {
      final res = await measuredRpc(_sb, 'get_feature_flags');
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      dlog('[PointsService] featureFlags error: $e');
    }
    return {};
  }

  /// Katalog paket topup (id, coins, price_idr, bonus_label, play_product_id).
  Future<List<Map<String, dynamic>>> listTopupPackages() async {
    try {
      final res = await measuredRpc(_sb, 'list_topup_packages');
      if (res is List) {
        return res
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (e) {
      dlog('[PointsService] listTopupPackages error: $e');
    }
    return const [];
  }

  /// Verifikasi pembelian Play ke server (edge function play-topup-verify).
  /// Return jumlah coin yang dikredit (0 bila gagal).
  Future<int> verifyPlayTopup({
    required String productId,
    required String purchaseToken,
  }) async {
    try {
      final res = await _sb.functions.invoke(
        'play-topup-verify',
        body: {
          'product_id': productId,
          'purchase_token': purchaseToken,
        },
      );
      final data = res.data;
      if (data is Map && data['coins'] != null) {
        return (data['coins'] as num).toInt();
      }
    } catch (e) {
      dlog('[PointsService] verifyPlayTopup error: $e');
    }
    return 0;
  }

  /// Potong akses harian (filter gender / nearby). Return {ok, charged, ...}.
  /// Raise 'YukCoin tidak cukup' bila saldo kurang.
  Future<Map<String, dynamic>> gateFeature(
    String feature, {
    String? priceFeature,
  }) async {
    final res = await measuredRpc(
      _sb,
      'gate_feature',
      params: {'p_feature': feature, if (priceFeature != null) 'p_price_feature': priceFeature},
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  Stream<bool> watchEnabled() async* {
    // TIDAK memakai `.stream()`: ia selalu `SELECT *` (supabase 2.16.x),
    // sementara `app_shared_secret` di-revoke dari anon/authenticated
    // (20260915120000_security_hardening.sql) → stream gagal 42501 dan
    // retry tanpa henti. Polling kolom eksplisit via RPC get_points_enabled
    // (sudah ada) menghindari itu tanpa melonggarkan hardening.
    yield await fetchEnabled();
    yield* Stream<void>.periodic(const Duration(seconds: 20))
        .asyncMap((_) => fetchEnabled());
  }

  /// Realtime saldo koin sendiri (profiles.points). Dipakai supaya saldo
  /// langsung update ketika ada koin masuk/keluar tanpa harus reload app.
  Stream<int> watchOwnPoints() async* {
    final id = uid;
    if (id == null) return;
    // stream() versi ini selalu SELECT *, tetapi profiles membatasi kolom.
    // Polling kolom points eksplisit mencegah 42501 pada security hardening.
    Future<int> fetch() async {
      final row = await _sb
          .from('profiles')
          .select('points')
          .eq('id', id)
          .maybeSingle();
      return ((row?['points'] as num?) ?? 0).toInt();
    }
    yield await fetch();
    yield* Stream<void>.periodic(const Duration(seconds: 20)).asyncMap((_) => fetch());
  }

  String? get uid => _sb.auth.currentUser?.id;

  /// Saldo wallet 3 bucket: {bonus, topup, earned, total, withdrawable}.
  Future<Map<String, dynamic>> getWallet() async {
    final res = await measuredRpc(_sb, 'get_wallet');
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'bonus': 0, 'topup': 0, 'earned': 0, 'total': 0, 'withdrawable': 0};
  }

  // ── YukCoin v2 ──────────────────────────────────────────────
  // Satu saldo (total) untuk UI, dipotong earned→bonus lewat spend_yukcoin.

  /// Saldo YukCoin terpadu: {total, bonus, earned}.
  Future<Map<String, dynamic>> getYukcoin() async {
    final res = await measuredRpc(_sb, 'get_yukcoin');
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'total': 0, 'bonus': 0, 'earned': 0};
  }

  /// Apakah fitur YukCoin v2 aktif untuk user ini (flag server / admin).
  Future<bool> yukcoinV2For() async {
    try {
      final res = await measuredRpc(_sb, 'yukcoin_v2_enabled_for');
      return res == true;
    } catch (e) {
      dlog('[PointsService] yukcoinV2For error: $e');
      return false;
    }
  }

  /// Status ringkas YukCoin v2: {active, total, bonus, earned, ghost, extra_slots}.
  Future<Map<String, dynamic>> yukcoinV2Status() async {
    try {
      final res = await measuredRpc(_sb, 'yukcoin_v2_status');
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      dlog('[PointsService] yukcoinV2Status error: $e');
    }
    return {
      'active': false,
      'total': 0,
      'bonus': 0,
      'earned': 0,
      'ghost': false,
      'extra_slots': 0,
    };
  }

  /// Slot foto tambahan milik user.
  Future<int> myExtraPhotoSlots() async {
    try {
      final res = await measuredRpc(_sb, 'my_extra_photo_slots');
      return (res as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Potong YukCoin (earned→bonus). Return {tier, remaining}.
  Future<Map<String, dynamic>> spendYukcoin(
    String feature,
    int amount, {
    String? ref,
  }) async {
    final res = await measuredRpc(
      _sb,
      'spend_yukcoin',
      params: {
        'p_user': uid,
        'p_feature': feature,
        'p_amount': amount,
        'p_ref': ?ref,
      },
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Undo pesan (soft delete). Return {ok, cost, remaining}.
  Future<Map<String, dynamic>> undoMessage(int messageId) async {
    final res = await measuredRpc(
      _sb,
      'undo_message_v2',
      params: {'p_message_id': messageId},
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Edit pesan. Return {ok, cost, remaining}.
  Future<Map<String, dynamic>> editMessage(int messageId, String newText) async {
    final res = await measuredRpc(
      _sb,
      'edit_message_v2',
      params: {'p_message_id': messageId, 'p_new_text': newText},
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Beli slot foto tambahan (default +5). Return {ok, cost, extra, remaining}.
  Future<Map<String, dynamic>> buyExtraPhotoSlots({int slots = 5}) async {
    final res = await measuredRpc(
      _sb,
      'buy_extra_photo_slots_v2',
      params: {'p_slots': slots},
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Beli ghost mode (invisible). Return {ok, cost, expires_at, remaining}.
  Future<Map<String, dynamic>> buyGhostMode({int days = 1}) async {
    final res = await measuredRpc(
      _sb,
      'buy_ghost_mode_v2',
      params: {'p_days': days},
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Apakah ghost mode (invisible) aktif.
  Future<bool> isGhostMode() async {
    try {
      final res = await measuredRpc(_sb, 'is_ghost_mode');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// Riwayat ledger (terbaru dulu). Field:
  /// id, bucket, type, amount, ref_id, metadata, created_at.
  ///
  /// Query langsung ke `coin_ledger` (RLS `coin_ledger_select_own`) dengan
  /// `.range()` supaya bisa paging — hasil identik dengan RPC get_ledger_history
  /// (yang sama-sama `order by created_at desc`, tapi tanpa paging).
  Future<List<Map<String, dynamic>>> pointHistory({
    int limit = 200,
    int offset = 0,
  }) async {
    final id = uid;
    if (id == null) return [];
    final res = await _sb
        .from('coin_ledger')
        .select('id,bucket,type,amount,ref_id,metadata,created_at')
        .eq('user_id', id)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return res.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<Map<String, dynamic>> dailyLoginBonus() async {
    final res = await measuredRpc(_sb, 'daily_login_bonus');
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'points': (res as num?)?.toInt() ?? 0, 'streak': 0, 'bonus': 0};
  }

  Future<int> deductChatPoint(String msgType) async {
    final res = await measuredRpc(_sb, 
      'deduct_chat_point',
      params: {'msg_type': msgType},
    );
    return (res as num).toInt();
  }

  Future<int> refundChatPoint(String msgType) async {
    final res = await measuredRpc(_sb, 
      'refund_chat_point',
      params: {'msg_type': msgType},
    );
    return (res as num).toInt();
  }

  Future<int> newChatBonus(String otherUid) async {
    final res = await measuredRpc(_sb, 
      'new_chat_bonus',
      params: {'other_uid': otherUid},
    );
    return (res as num).toInt();
  }

  Future<int> roomReadBonus() async {
    final res = await measuredRpc(_sb, 'room_read_bonus');
    return (res as num).toInt();
  }

  Future<int> oneTimeBonus(String actionKey, int bonus) async {
    final res = await measuredRpc(_sb, 
      'one_time_bonus',
      params: {'action_key': actionKey, 'bonus': bonus},
    );
    return (res as num).toInt();
  }

  /// Reward koin upload foto slot 1..5 (sekali per slot). Return total koin.
  Future<int> rewardPhotoSlot(int slotIndex) async {
    final res = await measuredRpc(_sb, 
      'reward_photo_slot',
      params: {'p_slot_index': slotIndex},
    );
    return (res as num).toInt();
  }

  /// Buka foto terkunci. mode 'once'|'perm'. Return {ok, points, mode}.
  Future<Map<String, dynamic>> unlockPhoto(String photoId, String mode) async {
    final res = await measuredRpc(_sb, 
      'unlock_photo',
      params: {'p_photo_id': photoId, 'p_mode': mode},
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Biaya buka foto (once, perm) dari app_settings.
  Future<(int, int)> photoCosts() async {
    try {
      final rows = await _sb
          .from('app_settings')
          .select('photo_unlock_once,photo_unlock_perm')
          .eq('id', 'global')
          .maybeSingle();
      final once = (rows?['photo_unlock_once'] as num?)?.toInt() ?? 5;
      final perm = (rows?['photo_unlock_perm'] as num?)?.toInt() ?? 20;
      return (once, perm);
    } catch (_) {
      return (5, 20);
    }
  }

  Future<int> registerBonus() async {
    final res = await measuredRpc(_sb, 'register_bonus');
    return (res as num).toInt();
  }

  /// Leaderboard. scope: 'weekly' | 'alltime'. Return {scope, entries[], me}.
  ///
  /// `offset` > 0 membutuhkan migration `points_leaderboard(text,int,int)`
  /// (supabase/migrations/20260913000000_leaderboard_history_pagination.sql);
  /// saat offset 0 param tidak dikirim — kompatibel dengan fungsi server lama.
  Future<Map<String, dynamic>> leaderboard(
    String scope, {
    int limit = 50,
    int offset = 0,
  }) async {
    final params = <String, dynamic>{
      'scope': scope,
      'row_limit': limit,
      if (offset > 0) 'row_offset': offset,
    };
    final res = await measuredRpc(_sb, 'points_leaderboard', params: params);
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'scope': scope, 'entries': [], 'me': null};
  }

  /// Status semua misi (harian/mingguan/sekali). tzOffset = menit offset lokal.
  Future<Map<String, dynamic>> quests(int tzOffsetMinutes) async {
    final res = await measuredRpc(_sb, 
      'points_quests',
      params: {'tz_offset_minutes': tzOffsetMinutes},
    );
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'points': 0, 'streak': 0, 'daily': [], 'weekly': [], 'oneTime': []};
  }

  /// Klaim misi mingguan. Return {points, claimed}.
  Future<Map<String, dynamic>> claimWeeklyQuest(
    String key,
    int tzOffsetMinutes,
  ) async {
    final res = await measuredRpc(_sb, 
      'claim_weekly_quest',
      params: {'quest_key': key, 'tz_offset_minutes': tzOffsetMinutes},
    );
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'points': 0, 'claimed': false};
  }

  /// Harga room (dual pricing) dari server.
  Future<Map<String, dynamic>> roomPricing() async {
    try {
      final res = await measuredRpc(_sb, 'room_pricing');
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      dlog('[PointsService] roomPricing error: $e');
    }
    return {
      'create_paid': 100,
      'create_pw_paid': 150,
      'join_paid': 5,
      'extend_paid': 50,
      'multiplier': 3,
    };
  }

  /// Subscribe creator (paid-only). Return {ok, points, ...}.
  Future<Map<String, dynamic>> subscribeCreator(
    String creatorUid, {
    int periods = 1,
  }) async {
    return subscribeCreatorRpc(_sb, creatorUid, periods: periods);
  }

  /// Klaim reward referral-install (sekali per referred).
  Future<Map<String, dynamic>> claimReferralReward() async {
    final res = await measuredRpc(_sb, 'claim_referral_reward');
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }
}
