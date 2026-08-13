import 'package:supabase_flutter/supabase_flutter.dart';

class AdminService {
  final SupabaseClient _sb;

  AdminService(this._sb);

  Future<Map<String, dynamic>> getStats() async {
    final res = await _sb.rpc('admin_stats');
    return res as Map<String, dynamic>;
  }

  /// Detail data per kategori untuk card Overview (list user/room).
  Future<Map<String, dynamic>> getStatsDetail() async {
    final res = await _sb.rpc('admin_stats_detail');
    return (res as Map<String, dynamic>?) ?? {};
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
  /// List chats dengan pagination. Return Map {'total': int, 'items': [...]}.
  Future<Map<String, dynamic>> listChats({int limit = 50, int offset = 0}) async {
    final res = await _sb.rpc(
      'admin_list_chats_page',
      params: {'p_limit': limit, 'p_offset': offset},
    );
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Ambil pesan chat dengan pagination (desc dari terbaru) — image_data
  /// kosong kecuali view-once. Foto biasa di-load lazy via PhotoCache.
  Future<List<Map<String, dynamic>>> getChatMessages(
    String chatId, {
    int limit = 100,
    int offset = 0,
  }) async {
    print('[ADMIN-SVC] getChatMessages chatId=$chatId limit=$limit offset=$offset');
    final res = await _sb.rpc(
      'admin_get_chat_messages_page',
      params: {'p_chat_id': chatId, 'p_limit': limit, 'p_offset': offset},
    );
    print('[ADMIN-SVC] getChatMessages result type=${res.runtimeType} len=${(res is List ? res.length : 'not list')}');
    final list = res is List ? res : <dynamic>[];
    return list.cast<Map<String, dynamic>>();
  }

  /// Fetch image_data satu foto (untuk retry / view-once admin).
  Future<String> getMessageImage(int messageId) async {
    final res = await _sb.rpc('admin_get_message_image', params: {'p_message_id': messageId});
    return (res as String?) ?? '';
  }

  /// Hapus chat + (opsional) user. Return {'ok': bool, 'photo_paths': [...]}.
  Future<Map<String, dynamic>> deleteChat(String chatId, List<String> deleteUserIds) async {
    final res = await _sb.rpc(
      'admin_delete_chat',
      params: {'p_chat_id': chatId, 'p_delete_user_ids': deleteUserIds},
    );
    return (res as Map<String, dynamic>?) ?? {};
  }
}
