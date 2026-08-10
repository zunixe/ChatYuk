import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminService {
  final SupabaseClient _sb;

  AdminService(this._sb);

  Future<Map<String, dynamic>> getStats() async {
    final res = await _sb.rpc('admin_stats');
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> massBonus(int bonus) async {
    final res = await _sb.rpc('admin_mass_bonus', params: {'bonus': bonus});
    return res as Map<String, dynamic>;
  }

  Future<int> resetAllPoints() async {
    final res = await _sb.rpc('admin_reset_points');
    return (res as num).toInt();
  }

  Future<bool> togglePointsSystem(bool enabled) async {
    final res = await _sb.rpc('admin_toggle_points', params: {'enabled': enabled});
    return res == true;
  }

  Future<void> forceLogout(String targetUid) async {
    await _sb.from('profiles').update({'fcm_token': ''}).eq('id', targetUid);
  }
}
