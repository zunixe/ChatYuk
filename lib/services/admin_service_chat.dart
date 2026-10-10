part of 'admin_service.dart';

// ignore_for_file: unused_element

mixin _AdminChatMx on _AdminBase {
  Future<Map<String, dynamic>> listDevices({
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await _rpc(
      'admin_list_devices',
      params: {'p_limit': limit, 'p_offset': offset},
    ).timeout(_openTimeout);
    return (res as Map<String, dynamic>?) ?? {'items': const [], 'total': 0};
  }

  /// Detail lengkap satu user: profil + device + chat partners + lokasi.
  Future<Map<String, dynamic>> getUserDetail(String uid) async {
    final res = await _rpc('admin_user_detail', params: {'p_uid': uid});
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Ringkasan atribusi: jumlah user per kanal (FB/IG/Google/TikTok/
  /// referral/organik) + kampanye teratas. [days] 0 = semua waktu.
  Future<Map<String, dynamic>> getAttributionSummary({int days = 0}) async {
    final res = await _rpc(
      'admin_attribution_summary',
      params: {'p_days': days},
    ).timeout(_openTimeout);
    return (res as Map<String, dynamic>?) ?? {'sources': const [], 'total': 0};
  }

  /// Daftar user per kanal atribusi. [source] kosong = semua kanal.
  Future<Map<String, dynamic>> listAttributionUsers({
    String source = '',
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await _rpc(
      'admin_attribution_users_page',
      params: {'p_source': source, 'p_limit': limit, 'p_offset': offset},
    ).timeout(_openTimeout);
    return (res as Map<String, dynamic>?) ?? {'items': const [], 'total': 0};
  }

  /// Daftar arsip user yang sudah dihapus. Bila [includePending] true,
  /// sertakan juga user ANON yang BELUM dihapus (nickname masih terpakai)
  /// sebagai item `pending` — admin bisa menghapusnya supaya nickname bebas.
  Future<Map<String, dynamic>> listDeleted({
    int limit = 100,
    int offset = 0,
    bool includePending = true,
  }) async {
    final res = await _rpc(
      'admin_list_deleted',
      params: {
        'p_limit': limit,
        'p_offset': offset,
        'p_include_pending': includePending,
      },
    ).timeout(_openTimeout);
    return (res as Map<String, dynamic>?) ?? {'items': const [], 'total': 0};
  }

  /// Hapus user ANON (belum terdaftar) oleh admin — membebaskan nickname.
  /// Return `{ok: true, nickname}` atau `{ok: false, error: 'REGISTERED'|
  /// 'DUMMY'|'NOT_FOUND'}`.
  Future<Map<String, dynamic>> deleteAnonUser(String uid) async {
    final res = await _rpc('admin_delete_anon_user', params: {'p_uid': uid});
    return (res as Map<String, dynamic>?) ?? {'ok': false};
  }

  /// Hapus baris arsip user dari tabel `deleted_users`.
  Future<void> deleteArchivedUsers(List<String> userIds) async {
    if (userIds.isEmpty) return;
    await _sb.from('deleted_users').delete().inFilter('user_id', userIds);
  }

  /// Riwayat device milik user yang sudah dihapus (via nickname snapshot).
  Future<List<Map<String, dynamic>>> getDeletedDeviceHistory(
    String nickname,
  ) async {
    final res = await _rpc(
      'admin_deleted_device_history',
      params: {'p_nickname': nickname},
    );
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  /// Riwayat GPS/IP milik user yang sudah dihapus (dari arsip deleted_users).
  Future<List<Map<String, dynamic>>> getDeletedLocationHistory(
    String userId,
  ) async {
    final res = await _rpc(
      'admin_deleted_location_history',
      params: {'p_user_id': userId},
    );
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  /// Statistik penggunaan data Supabase (DB/storage/kuota + pertumbuhan).
  /// WAJIB timeout (kasus nyata: tanpa ini koneksi stall = spinner selamanya).
  Future<Map<String, dynamic>> getStorageStats() async {
    final res = await _rpc('admin_storage_stats').timeout(_openTimeout);
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Breakdown ukuran tabel terbesar (DB Ringkasan diklik).
  /// Return `{db_bytes, tables: [{schema, table, total_bytes,
  /// table_bytes, index_bytes, rows_est}]}`.
  Future<Map<String, dynamic>> getTableSizes({int limit = 30}) async {
    final res = await _rpc(
      'admin_table_sizes',
      params: {'p_limit': limit},
    ).timeout(_openTimeout);
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Organisasi monitor chat (PIN + kategori) — agar tersinkron antar HP
  /// admin. Return {'pinned_chat_ids': [...], 'category_list': [...],
  /// 'category_map': {...}}. {} bila gagal.
  Future<Map<String, dynamic>> getChatOrg() async {
    try {
      final res = await _rpc('admin_get_chat_org').timeout(_openTimeout);
      return (res as Map<String, dynamic>?) ?? {};
    } catch (e) {
      dlog('[ADMIN] getChatOrg error: $e');
      return {};
    }
  }

  /// Simpan organisasi monitor chat ke server (sync antar HP admin).
  /// Field null = tidak diubah (partial update).
  Future<bool> setChatOrg({
    List<String>? pinned,
    List<String>? categories,
    Map<String, String>? map,
  }) async {
    try {
      final res = await _rpc(
        'admin_set_chat_org',
        params: {'p_pinned': pinned, 'p_categories': categories, 'p_map': map},
      ).timeout(_openTimeout);
      return res is Map<String, dynamic>;
    } catch (e) {
      dlog('[ADMIN] setChatOrg error: $e');
      return false;
    }
  }

  /// Daftar user terdaftar (registrasi email) — nickname + email + tgl.
  Future<Map<String, dynamic>> listRegistrations({
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await _rpc(
      'admin_registrations_list',
      params: {'p_limit': limit, 'p_offset': offset},
    );
    return (res as Map<String, dynamic>?) ?? {'items': const [], 'total': 0};
  }

  /// UID dummy + device-ter-exclude — untuk filter client-side (peta realtime).
  Future<Set<String>> fetchHiddenUids() async {
    final res = await _rpc('admin_hidden_uids');
    final m = res as Map<String, dynamic>?;
    if (m == null) return const {};
    final out = <String>{};
    for (final k in const ['dummy', 'excluded']) {
      for (final v in (m[k] as List? ?? const [])) {
        out.add('$v');
      }
    }
    return out;
  }

  /// Pemakaian Cloudflare Realtime TURN (kuota 1 TB/bulan free tier).
  /// Return {configured: bool, day_bytes, week_bytes, month_bytes,
  /// quota_bytes} atau {configured:false} bila secrets belum diset.
  /// WAJIB timeout — edge function stall = bagian CF "..." selamanya.
  Future<Map<String, dynamic>> getCfUsage() async {
    final res = await _sb.functions
        .invoke('admin-cf-usage')
        .timeout(_openTimeout);
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
    await _rpc(
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
  Future<bool> isNicknameAvailable(
    String nickname, {
    String? excludeUid,
  }) async {
    var query = _sb.from('profiles').select('id');
    if (excludeUid != null && excludeUid.isNotEmpty) {
      query = query.neq('id', excludeUid);
    }
    final res = await query.eq('nickname', nickname).limit(1).maybeSingle();
    return res == null;
  }

  /// Varian ber-paginasi: `{items, total, limit, offset}`. Menggantikan
  /// `listDummies()` (tanpa limit, sudah dihapus) supaya polling tidak
  /// menarik seluruh tabel.
  Future<Map<String, dynamic>> listDummiesPage({
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _rpc(
      'admin_list_dummies_page',
      params: {'p_limit': limit, 'p_offset': offset},
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Riwayat story harian satu dummy N hari terakhir: `{kind, story_expected,
  /// days:[{date, has_story, story, created_at}]}`. Untuk panel admin —
  /// ketahuan hari mana yang belum ke-generate.
  Future<Map<String, dynamic>> getDummyStories(
    String uid, {
    int days = 14,
  }) async {
    final res = await _rpc(
      'admin_get_dummy_stories',
      params: {'p_uid': uid, 'p_days': days},
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Generate story hari ini untuk satu dummy biasa dari tombol admin.
  Future<Map<String, dynamic>> generateDummyStory(
    String uid, {
    required String storyDate,
  }) async {
    final res = await _sb.functions.invoke(
      'ai-daily-life',
      body: {'dummy_uid': uid, 'story_date': storyDate},
    );
    final data = res.data;
    if (data is Map && data['ok'] == false) {
      throw StateError('${data['error'] ?? 'story_generation_failed'}');
    }
    return data is Map ? Map<String, dynamic>.from(data) : {};
  }

  /// Set status dummy: 'online' | 'idle' | 'offline' | 'invisible'.
  Future<void> setDummyStatus(String uid, String status) async {
    await _rpc(
      'admin_set_dummy_status',
      params: {'p_uid': uid, 'p_status': status},
    );
  }

  /// Bangunkan dummy N menit (default 30): AI melek & membalas walau jam
  /// tidur, presence dipaksa online. Lewat masa → normal otomatis.
  Future<void> wakeDummy(String uid, {int minutes = 30}) async {
    await _rpc(
      'admin_wake_dummy',
      params: {'p_uid': uid, 'p_minutes': minutes},
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
    List<int>? activeHours,
    // Model LLM per-dummy: id model (mis. 'mimo-v2.5-free'), 'NULL'
    // (uppercase) = reset ke default global, null = tidak diubah.
    String? model,
    // Toggle kirim foto: true = AI bisa kirim foto, false = ditolak.
    bool? photosEnabled,
  }) async {
    await _rpc(
      'admin_set_dummy_ai',
      params: {
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
        // Jadwal jam online: selalu dikirim (list dari editor grid).
        'p_active_hours': activeHours ?? const <int>[],
        if (model != null) 'p_model': model,
        if (photosEnabled != null) 'p_photos_enabled': photosEnabled,
      },
    );
  }

  /// Baca setting AI global (panggilan tanpa argumen = get).
  Future<Map<String, dynamic>> getAiSettings() async {
    final res = await _rpc('admin_ai_settings');
    return (res as Map<String, dynamic>?) ?? const {};
  }

  /// Generate jadwal kehadiran AI otomatis dari kebiasaan jam aktif dummy
  /// (riwayat chat 14 hari). Return {'hours': [8,9,...]} jam WIB.
  Future<List<int>> autoScheduleAi(String uid) async {
    final res = await _rpc('admin_ai_autoschedule', params: {'p_uid': uid});
    final hours = (res as Map<String, dynamic>?)?['hours'];
    if (hours is List) {
      return hours.map((e) => (e as num).toInt()).toList()..sort();
    }
    return const [];
  }

  /// Ubah setting AI global — hanya key yang diisi yang berubah.
}
