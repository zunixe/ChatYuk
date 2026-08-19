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

  /// Ambil nominal pengaturan poin (untuk form admin).
  Future<Map<String, dynamic>> getPointSettings() async {
    final res = await _sb.rpc('admin_get_point_settings');
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Simpan nominal pengaturan poin. p = {key: value} (int atau string).
  Future<Map<String, dynamic>> updatePointSettings(Map<String, dynamic> p) async {
    final res = await _sb.rpc('admin_update_point_settings', params: {'p': p});
    return res is Map ? Map<String, dynamic>.from(res) : {};
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
    final res = await _sb.rpc(
      'admin_get_chat_messages_page',
      params: {'p_chat_id': chatId, 'p_limit': limit, 'p_offset': offset},
    );
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

  // ── Admin Dummy Accounts ──
  /// Daftarkan akun dummy. Akun baru dibuat via signUp (email dikonfirmasi
  /// server); kalau email sudah ada, cukup diverifikasi password-nya.
  /// Return {'ok': bool, 'uid': String?}.
  /// Daftarkan akun dummy ANONYMOUS (via edge function + GoTrue,
  /// tanpa email/password & tanpa rate-limit signup).
  Future<Map<String, dynamic>> registerDummy({
    required String nickname,
    String gender = 'male',
    int age = 25,
    String country = 'Indonesia',
    String city = 'Jakarta',
  }) async {
    final res = await _sb.functions.invoke(
      'dummy-manage',
      body: {
        'action': 'create',
        'nickname': nickname,
        'gender': gender,
        'age': age,
        'country': country,
        'city': city,
      },
    );
    if (res.status >= 300) {
      throw Exception('create_failed');
    }
    return res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
  }

  /// Update profil dummy (gender/umur/negara/kota) — tanpa menyentuh status.
  Future<void> updateDummyProfile({
    required String uid,
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
  }) async {
    await _sb.rpc('admin_update_dummy_profile', params: {
      'p_uid': uid,
      'p_nickname': nickname,
      'p_gender': gender,
      'p_age': age,
      'p_country': country,
      'p_city': city,
    });
  }

  /// List semua akun dummy: uid, email, password, nickname, status, last_seen.
  Future<List<Map<String, dynamic>>> listDummies() async {
    final res = await _sb.rpc('admin_list_dummies');
    final list = res is List ? res : <dynamic>[];
    return list.cast<Map<String, dynamic>>();
  }

  /// Set status dummy: 'online' | 'idle' | 'offline'.
  Future<void> setDummyStatus(String uid, String status) async {
    await _sb.rpc('admin_set_dummy_status', params: {'p_uid': uid, 'p_status': status});
  }

  /// Hapus akun dummy + history chat-nya. Return {'ok': bool, 'chats_deleted': int}.
  Future<Map<String, dynamic>> deleteDummy(String uid) async {
    final res = await _sb.rpc('admin_delete_dummy', params: {'p_uid': uid});
    return (res as Map<String, dynamic>?) ?? {};
  }

  // ── Pesan Kontak (Hubungi Kami) ──
  /// List pesan kontak dengan pagination. Return {'total': int, 'items': [...]}.
  Future<Map<String, dynamic>> listContactMessages({int limit = 50, int offset = 0}) async {
    final res = await _sb.rpc(
      'admin_contact_messages_page',
      params: {'p_limit': limit, 'p_offset': offset},
    );
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Tandai pesan terbaca / belum terbaca.
  Future<void> setContactRead(String id, {bool read = true}) async {
    await _sb.rpc('admin_contact_set_read', params: {'p_id': id, 'p_read': read});
  }

  /// Hapus pesan kontak.
  Future<void> deleteContactMessage(String id) async {
    await _sb.rpc('admin_contact_delete', params: {'p_id': id});
  }
}
