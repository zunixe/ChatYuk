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

  // ── Admin Chat Monitor ──
  Future<List<Map<String, dynamic>>> listChats() async {
    final res = await _sb.rpc('admin_list_chats');
    final list = res as List<dynamic>? ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Ambil semua pesan chat — image_data kosong kecuali view-once.
  /// Foto biasa di-load lazy via PhotoCache + admin_get_message_image.
  Future<List<Map<String, dynamic>>> getChatMessages(String chatId) async {
    final res = await _sb.rpc('admin_get_chat_messages', params: {'p_chat_id': chatId});
    final list = res as List<dynamic>? ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Fetch image_data satu foto (untuk retry / view-once admin).
  Future<String> getMessageImage(int messageId) async {
    final res = await _sb.rpc('admin_get_message_image', params: {'p_message_id': messageId});
    return (res as String?) ?? '';
  }
}
