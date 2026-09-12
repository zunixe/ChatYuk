import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/active_call_model.dart';

class AdminService {
  final SupabaseClient _sb;

  AdminService(this._sb);

  Future<Map<String, dynamic>> getStats() async {
    final res = await _sb.rpc('admin_stats');
    return res as Map<String, dynamic>;
  }

  /// Paksa server menghitung ulang statistik (pull-to-refresh).
  Future<Map<String, dynamic>> getStatsForce() async {
    final res = await _sb.rpc('admin_stats_force');
    return res as Map<String, dynamic>;
  }

  /// Detail data per kategori untuk card Overview (list user/room).
  Future<Map<String, dynamic>> getStatsDetail() async {
    final res = await _sb.rpc('admin_stats_detail');
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Jumlah registrasi email per hari di bulan tertentu (bar chart Ringkasan).
  Future<Map<int, int>> fetchRegistrationsDaily(int year, int month) async {
    final res = await _sb.rpc(
      'admin_registrations_daily',
      params: {'p_year': year, 'p_month': month},
    );
    final map = <int, int>{};
    for (final r in (res as List? ?? const [])) {
      map[(r['day'] as num).toInt()] = (r['count'] as num).toInt();
    }
    return map;
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
    final res = await _sb.rpc(
      'admin_toggle_points',
      params: {'enabled': enabled},
    );
    return res == true;
  }

  /// Ambil nominal pengaturan poin (untuk form admin).
  Future<Map<String, dynamic>> getPointSettings() async {
    final res = await _sb.rpc('admin_get_point_settings');
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Simpan nominal pengaturan poin. p = {key: value} (int atau string).
  Future<Map<String, dynamic>> updatePointSettings(
    Map<String, dynamic> p,
  ) async {
    final res = await _sb.rpc('admin_update_point_settings', params: {'p': p});
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  Future<void> forceLogout(String targetUid) async {
    await _sb.from('profiles').update({'fcm_token': ''}).eq('id', targetUid);
  }

  // ── Admin Chat Monitor ──
  /// List chats dengan pagination. Return Map {'total': int, 'items': [...]}.
  Future<Map<String, dynamic>> listChats({
    int limit = 50,
    int offset = 0,
  }) async {
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

  /// last_read_at chat (uid → timestamp mentah) untuk samakan centang-2
  /// monitor dengan chat asli. {} bila gagal.
  Future<Map<String, String>> getChatLastRead(String chatId) async {
    try {
      final res = await _sb.rpc(
        'admin_get_chat_last_read',
        params: {'p_chat_id': chatId},
      );
      final map = res as Map<String, dynamic>?;
      if (map == null) return {};
      return map.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  /// Fetch image_data satu foto (untuk retry / view-once admin).
  Future<String> getMessageImage(int messageId) async {
    final res = await _sb.rpc(
      'admin_get_message_image',
      params: {'p_message_id': messageId},
    );
    return (res as String?) ?? '';
  }

  /// Hapus chat + (opsional) user. Return {'ok': bool, 'photo_paths': [...]}.
  Future<Map<String, dynamic>> deleteChat(
    String chatId,
    List<String> deleteUserIds,
  ) async {
    final res = await _sb.rpc(
      'admin_delete_chat',
      params: {'p_chat_id': chatId, 'p_delete_user_ids': deleteUserIds},
    );
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Daftar call 1:1 yang sedang aktif (audio/video) — untuk badge monitor
  /// dan fitur pantau call di admin panel.
  Future<List<ActiveCallInfo>> getActiveCalls() async {
    final res = await _sb.rpc('admin_active_calls');
    final list = res is List ? res : <dynamic>[];
    return list
        .map(
          (e) => ActiveCallInfo.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
  }

  /// Akhiri call zombie: ringing kadaluarsa & answered tanpa heartbeat.
  /// Return jumlah row yang diakhiri. Hanya admin.
  Future<int> sweepStaleCalls() async {
    final res = await _sb.rpc('admin_sweep_calls');
    return (res as num?)?.toInt() ?? 0;
  }

  /// Daftar semua device semua user (pelacakan admin).
  Future<Map<String, dynamic>> listDevices({
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await _sb.rpc('admin_list_devices', params: {
      'p_limit': limit,
      'p_offset': offset,
    });
    return (res as Map<String, dynamic>?) ?? {'items': const [], 'total': 0};
  }

  /// Detail lengkap satu user: profil + device + chat partners + lokasi.
  Future<Map<String, dynamic>> getUserDetail(String uid) async {
    final res = await _sb.rpc('admin_user_detail', params: {'p_uid': uid});
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Daftar arsip user yang sudah dihapus.
  Future<Map<String, dynamic>> listDeleted({
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await _sb.rpc('admin_list_deleted', params: {
      'p_limit': limit,
      'p_offset': offset,
    });
    return (res as Map<String, dynamic>?) ?? {'items': const [], 'total': 0};
  }

  /// Riwayat device milik user yang sudah dihapus (via nickname snapshot).
  Future<List<Map<String, dynamic>>> getDeletedDeviceHistory(
    String nickname,
  ) async {
    final res = await _sb.rpc(
      'admin_deleted_device_history',
      params: {'p_nickname': nickname},
    );
    if (res is List) {
      return res
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return const [];
  }

  /// Statistik penggunaan data Supabase (DB/storage/kuota + pertumbuhan).
  Future<Map<String, dynamic>> getStorageStats() async {
    final res = await _sb.rpc('admin_storage_stats');
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Daftar user terdaftar (registrasi email) — nickname + email + tgl.
  Future<Map<String, dynamic>> listRegistrations({
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await _sb.rpc('admin_registrations_list', params: {
      'p_limit': limit,
      'p_offset': offset,
    });
    return (res as Map<String, dynamic>?) ?? {'items': const [], 'total': 0};
  }

  /// Pemakaian Cloudflare Realtime TURN (kuota 1 TB/bulan free tier).
  /// Return {configured: bool, day_bytes, week_bytes, month_bytes,
  /// quota_bytes} atau {configured:false} bila secrets belum diset.
  Future<Map<String, dynamic>> getCfUsage() async {
    final res = await _sb.functions.invoke('admin-cf-usage');
    return res.data is Map ? Map<String, dynamic>.from(res.data as Map) : {};
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
    return res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : <String, dynamic>{};
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
    await _sb.rpc(
      'admin_update_dummy_profile',
      params: {
        'p_uid': uid,
        'p_nickname': nickname,
        'p_gender': gender,
        'p_age': age,
        'p_country': country,
        'p_city': city,
      },
    );
  }

  /// Cek nickname tersedia untuk dummy [excludeUid] (abaikan miliknya
  /// sendiri saat edit). Nickname unik di profiles — tanpa pre-check ini,
  /// create/edit dummy dengan nickname duplikat gagal di server dengan
  /// error generik. Case-sensitive exact match (server RPC yang validasi
  /// case-insensitive sebagai sumber kebenaran).
  Future<bool> isNicknameAvailable(String nickname, {String? excludeUid}) async {
    var query = _sb.from('profiles').select('id');
    if (excludeUid != null && excludeUid.isNotEmpty) {
      query = query.neq('id', excludeUid);
    }
    final res = await query.eq('nickname', nickname).limit(1).maybeSingle();
    return res == null;
  }

  /// List semua akun dummy: uid, email, password, nickname, status, last_seen.
  Future<List<Map<String, dynamic>>> listDummies() async {
    final res = await _sb.rpc('admin_list_dummies');
    final list = res is List ? res : <dynamic>[];
    return list.cast<Map<String, dynamic>>();
  }

  /// Set status dummy: 'online' | 'idle' | 'offline'.
  Future<void> setDummyStatus(String uid, String status) async {
    await _sb.rpc(
      'admin_set_dummy_status',
      params: {'p_uid': uid, 'p_status': status},
    );
  }

  /// Toggle AI mode dummy + persona ({} = otomatis dari profil dummy).
  Future<void> setDummyAi(
    String uid,
    bool enabled,
    Map<String, dynamic> persona, {
    bool? scheduleAuto,
    bool? guardEnabled,
    bool? noRateLimit,
    int? maxReplies,
    int? minInterval,
  }) async {
    await _sb.rpc('admin_set_dummy_ai', params: {
      'p_uid': uid,
      'p_enabled': enabled,
      'p_persona': persona,
      if (scheduleAuto != null) 'p_schedule_auto': scheduleAuto,
      // null = ikuti global — kirim key-nya selalu supaya bisa reset.
      'p_guard_enabled': guardEnabled,
      // Rate limit per-dummy: null = ikut global / reset override.
      'p_max_replies': maxReplies,
      'p_min_interval': minInterval,
      if (noRateLimit != null) 'p_no_rate_limit': noRateLimit,
    });
  }

  /// Baca setting AI global (panggilan tanpa argumen = get).
  Future<Map<String, dynamic>> getAiSettings() async {
    final res = await _sb.rpc('admin_ai_settings');
    return (res as Map<String, dynamic>?) ?? const {};
  }

  /// Generate jadwal kehadiran AI otomatis dari kebiasaan jam aktif dummy
  /// (riwayat chat 14 hari). Return {'hours': [8,9,...]} jam WIB.
  Future<List<int>> autoScheduleAi(String uid) async {
    final res = await _sb.rpc('admin_ai_autoschedule', params: {'p_uid': uid});
    final hours = (res as Map<String, dynamic>?)?['hours'];
    if (hours is List) {
      return hours.map((e) => (e as num).toInt()).toList()..sort();
    }
    return const [];
  }

  /// Ubah setting AI global — hanya key yang diisi yang berubah.
  Future<Map<String, dynamic>> setAiSettings({
    bool? globalEnabled,
    int? maxReplies,
    int? minInterval,
    bool? guardEnabled,
    String? apiBase,
    String? apiKey,
    String? defaultModel,
  }) async {
    final params = <String, dynamic>{
      if (globalEnabled != null) 'p_global_enabled': globalEnabled,
      if (maxReplies != null) 'p_max_replies': maxReplies,
      if (minInterval != null) 'p_min_interval': minInterval,
      if (guardEnabled != null) 'p_guard_enabled': guardEnabled,
      if (apiBase != null && apiBase.isNotEmpty) 'p_api_base': apiBase,
      if (apiKey != null && apiKey.isNotEmpty) 'p_api_key': apiKey,
      if (defaultModel != null && defaultModel.isNotEmpty)
        'p_default_model': defaultModel,
    };
    final res = await _sb.rpc('admin_ai_settings', params: params);
    return (res as Map<String, dynamic>?) ?? const {};
  }

  /// Daftar provider AI (id, label, base, key, model, is_active).
  Future<List<Map<String, dynamic>>> getAiProviders() async {
    final res = await _sb.rpc('admin_ai_provider_list');
    if (res is List) {
      return res
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    return const [];
  }

  /// Simpan provider (id kosong = tambah baru, slug otomatis).
  /// Return row tersimpan.
  Future<Map<String, dynamic>> saveAiProvider({
    String? id,
    String? label,
    String? apiBase,
    String? apiKey,
    String? defaultModel,
  }) async {
    final res = await _sb.rpc('admin_ai_provider_save', params: {
      if (id != null) 'p_id': id,
      if (label != null) 'p_label': label,
      if (apiBase != null) 'p_api_base': apiBase,
      if (apiKey != null) 'p_api_key': apiKey,
      if (defaultModel != null) 'p_default_model': defaultModel,
    });
    return (res as Map<String, dynamic>?) ?? const {};
  }

  /// Hapus provider (yang aktif tidak bisa — aktifkan lain dulu).
  Future<void> deleteAiProvider(String id) async {
    await _sb.rpc('admin_ai_provider_delete', params: {'p_id': id});
  }

  /// Aktifkan provider (yang dipakai edge function).
  Future<void> activateAiProvider(String id) async {
    await _sb.rpc('admin_ai_provider_activate', params: {'p_id': id});
  }

  /// Hapus akun dummy + history chat-nya. Return {'ok': bool, 'chats_deleted': int}.
  Future<Map<String, dynamic>> deleteDummy(String uid) async {
    final res = await _sb.rpc('admin_delete_dummy', params: {'p_uid': uid});
    return (res as Map<String, dynamic>?) ?? {};
  }

  // ── Pesan Kontak (Hubungi Kami) ──
  /// List pesan kontak dengan pagination. Return {'total': int, 'items': [...]}.
  Future<Map<String, dynamic>> listContactMessages({
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _sb.rpc(
      'admin_contact_messages_page',
      params: {'p_limit': limit, 'p_offset': offset},
    );
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Tandai pesan terbaca / belum terbaca.
  Future<void> setContactRead(String id, {bool read = true}) async {
    await _sb.rpc(
      'admin_contact_set_read',
      params: {'p_id': id, 'p_read': read},
    );
  }

  /// Hapus pesan kontak.
  Future<void> deleteContactMessage(String id) async {
    await _sb.rpc('admin_contact_delete', params: {'p_id': id});
  }
}
