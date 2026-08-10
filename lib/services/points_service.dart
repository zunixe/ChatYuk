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

  Future<int> dailyLoginBonus() async {
    final res = await _sb.rpc('daily_login_bonus');
    return (res as num).toInt();
  }

  Future<int> deductChatPoint(String msgType) async {
    final res = await _sb.rpc('deduct_chat_point', params: {'msg_type': msgType});
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
}
