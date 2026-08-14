import 'dart:async';
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

  Future<Map<String, dynamic>> dailyLoginBonus() async {
    final res = await _sb.rpc('daily_login_bonus');
    if (res is Map) return Map<String, dynamic>.from(res);
    return {'points': (res as num?)?.toInt() ?? 0, 'streak': 0, 'bonus': 0};
  }

  Future<int> deductChatPoint(String msgType) async {
    final res = await _sb.rpc('deduct_chat_point', params: {'msg_type': msgType});
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
}
