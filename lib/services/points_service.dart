import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PointsService {
  final SupabaseClient _sb;

  PointsService([SupabaseClient? sb]) : _sb = sb ?? Supabase.instance.client;

  Future<bool> fetchEnabled() async {
    final res = await _sb.rpc('get_points_enabled');
    return res == true;
  }

  Stream<bool> watchEnabled() {
    return _sb
        .from('app_settings')
        .stream(primaryKey: ['id'])
        .map((rows) {
          final matching = rows.where((r) => r['id'] == 'global').toList();
          return matching.isEmpty ? true : matching.first['points_enabled'] == true;
        });
  }

  /// Realtime saldo koin sendiri (profiles.points). Dipakai supaya saldo
  /// langsung update ketika ada koin masuk/keluar tanpa harus reload app.
  Stream<int> watchOwnPoints() {
    final id = uid;
    if (id == null) return const Stream.empty();
    return _sb
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map((rows) {
          final mine = rows.where((r) => r['id'] == id).toList();
          if (mine.isEmpty) return 0;
          return ((mine.first['points'] as num?) ?? 0).toInt();
        });
  }

  String? get uid => _sb.auth.currentUser?.id;

  /// Saldo wallet 3 bucket: {bonus, topup, earned, total, withdrawable}.
  Future<Map<String, dynamic>> getWallet() async {
    final res = await _sb.rpc('get_wallet');
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'bonus': 0, 'topup': 0, 'earned': 0, 'total': 0, 'withdrawable': 0};
  }

  /// Riwayat ledger (terbaru dulu). Field:
  /// id, bucket, type, amount, ref_id, metadata, created_at.
  Future<List<Map<String, dynamic>>> pointHistory({int limit = 200}) async {
    final res = await _sb.rpc('get_ledger_history', params: {'row_limit': limit});
    if (res is List) {
      return res.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>> dailyLoginBonus() async {
    final res = await _sb.rpc('daily_login_bonus');
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'points': (res as num?)?.toInt() ?? 0, 'streak': 0, 'bonus': 0};
  }

  Future<int> deductChatPoint(String msgType) async {
    final res = await _sb.rpc('deduct_chat_point', params: {'msg_type': msgType});
    return (res as num).toInt();
  }

  Future<int> refundChatPoint(String msgType) async {
    final res = await _sb.rpc('refund_chat_point', params: {'msg_type': msgType});
    return (res as num).toInt();
  }

  Future<int> newChatBonus(String otherUid) async {
    final res = await _sb.rpc('new_chat_bonus', params: {'other_uid': otherUid});
    return (res as num).toInt();
  }

  Future<int> roomReadBonus() async {
    final res = await _sb.rpc('room_read_bonus');
    return (res as num).toInt();
  }

  Future<int> oneTimeBonus(String actionKey, int bonus) async {
    final res = await _sb.rpc('one_time_bonus', params: {'action_key': actionKey, 'bonus': bonus});
    return (res as num).toInt();
  }

  /// Reward koin upload foto slot 1..5 (sekali per slot). Return total koin.
  Future<int> rewardPhotoSlot(int slotIndex) async {
    final res = await _sb.rpc('reward_photo_slot', params: {'p_slot_index': slotIndex});
    return (res as num).toInt();
  }

  /// Buka foto terkunci. mode 'once'|'perm'. Return {ok, points, mode}.
  Future<Map<String, dynamic>> unlockPhoto(String photoId, String mode) async {
    final res = await _sb.rpc('unlock_photo', params: {'p_photo_id': photoId, 'p_mode': mode});
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
    final res = await _sb.rpc('register_bonus');
    return (res as num).toInt();
  }

  /// Leaderboard. scope: 'weekly' | 'alltime'. Return {scope, entries[], me}.
  Future<Map<String, dynamic>> leaderboard(String scope, {int limit = 50}) async {
    final res = await _sb.rpc('points_leaderboard',
        params: {'scope': scope, 'row_limit': limit});
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'scope': scope, 'entries': [], 'me': null};
  }

  /// Status semua misi (harian/mingguan/sekali). tzOffset = menit offset lokal.
  Future<Map<String, dynamic>> quests(int tzOffsetMinutes) async {
    final res = await _sb.rpc('points_quests',
        params: {'tz_offset_minutes': tzOffsetMinutes});
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'points': 0, 'streak': 0, 'daily': [], 'weekly': [], 'oneTime': []};
  }

  /// Klaim misi mingguan. Return {points, claimed}.
  Future<Map<String, dynamic>> claimWeeklyQuest(String key, int tzOffsetMinutes) async {
    final res = await _sb.rpc('claim_weekly_quest',
        params: {'quest_key': key, 'tz_offset_minutes': tzOffsetMinutes});
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'points': 0, 'claimed': false};
  }

  /// Harga room (dual pricing) dari server.
  Future<Map<String, dynamic>> roomPricing() async {
    try {
      final res = await _sb.rpc('room_pricing');
      if (res is Map) return Map<String, dynamic>.from(res);
    } catch (e) {
      debugPrint('[PointsService] roomPricing error: $e');
    }
    return {'create_paid': 100, 'create_pw_paid': 150, 'join_paid': 5, 'extend_paid': 50, 'multiplier': 3};
  }

  /// Subscribe creator (paid-only). Return {ok, points, ...}.
  Future<Map<String, dynamic>> subscribeCreator(String creatorUid, {int periods = 1}) async {
    final res = await _sb.rpc('subscribe_creator',
        params: {'p_creator': creatorUid, 'p_periods': periods});
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Klaim reward referral-install (sekali per referred).
  Future<Map<String, dynamic>> claimReferralReward() async {
    final res = await _sb.rpc('claim_referral_reward');
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }
}
