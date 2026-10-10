part of 'admin_service.dart';

// ignore_for_file: unused_element

mixin _AdminStatsMx on _AdminBase {
  Future<Set<String>> getExcludedDevices() async {
    final cached = _excludedCache;
    final at = _excludedAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _excludedTtl) {
      return cached;
    }
    try {
      final rows = await _sb
          .from('app_settings')
          .select('excluded_devices')
          .eq('id', 'global')
          .maybeSingle()
          .timeout(const Duration(seconds: 2));
      final list = rows?['excluded_devices'] as List?;
      final out = {for (final e in list ?? const []) '$e'};
      _excludedCache = out;
      _excludedAt = DateTime.now();
      return out;
    } catch (_) {
      return const {};
    }
  }

  // Timeout jalur buka panel: tanpa ini, koneksi stall membuat future
  // tidak pernah selesai → spinner selamanya (panel "blank"/"hang").
  // Gagal-timeout ditangkap provider → tampil error/stale, bukan blank.
  // 10 dtk (dulu 30): koneksi basi setelah idle bisa menggantung; timeout
  // lebih pendek membuat kegagalan cepat & bisa di-retry, bukan menunggu
  // 30 dtk terasa "hang". RPC admin normal terukur < 500ms.

  Future<Map<String, dynamic>> getStats() async {
    final res = await _rpc('admin_stats').timeout(_openTimeout);
    return res as Map<String, dynamic>;
  }

  /// Paksa server menghitung ulang statistik (pull-to-refresh).
  Future<Map<String, dynamic>> getStatsForce() async {
    final res = await _rpc('admin_stats_force').timeout(_openTimeout);
    return res as Map<String, dynamic>;
  }

  /// Detail data per kategori untuk card Overview (list user/room).
  Future<Map<String, dynamic>> getStatsDetail() async {
    final res = await _rpc('admin_stats_detail').timeout(_openTimeout);
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Daftar user statistik ber-paginasi (ganti list full dari detail).
  /// kind: 'all' | 'active' | 'registered' | 'anonymous'.
  /// Return {'items': [...], 'total': n}. Otomatis terukur `admin.*` via _rpc.
  Future<Map<String, dynamic>> listStatsUsers(
    String kind, {
    int limit = 100,
    int offset = 0,
  }) async {
    final res = await _rpc(
      'admin_stats_users_page',
      params: {'p_kind': kind, 'p_limit': limit, 'p_offset': offset},
    ).timeout(_openTimeout);
    return (res as Map<String, dynamic>?) ?? {'items': const [], 'total': 0};
  }

  /// Jumlah registrasi email per hari di bulan tertentu (bar chart Ringkasan).
  Future<Map<int, int>> fetchRegistrationsDaily(int year, int month) async {
    final res = await _rpc(
      'admin_registrations_daily',
      params: {'p_year': year, 'p_month': month},
    );
    final map = <int, int>{};
    for (final r in (res as List? ?? const [])) {
      map[(r['day'] as num).toInt()] = (r['count'] as num).toInt();
    }
    return map;
  }

  /// KPI registrasi (total, konversi, baru bulan ini, avg/hari, hari terbaik,
  /// aktif hari ini) untuk kartu Ringkasan CEO.
  Future<Map<String, dynamic>> fetchRegistrationKpis() async {
    final res = await _rpc('admin_registration_kpis');
    return (res as Map<String, dynamic>?) ?? const {};
  }

  /// Sebaran user per NEGARA → [{country, count, registered}] desc.
  Future<List<Map<String, dynamic>>> fetchCountryStats() async {
    final res = await _rpc('admin_country_stats').timeout(_openTimeout);
    return ((res as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Sebaran user per KOTA dalam satu negara → [{city, count, registered}].
  Future<List<Map<String, dynamic>>> fetchCityStats(String country) async {
    final res = await _rpc(
      'admin_city_stats',
      params: {'p_country': country},
    ).timeout(_openTimeout);
    return ((res as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Total registrasi per bulan (tren N bulan terakhir) → map 'YYYY-MM' → n.
  Future<List<Map<String, dynamic>>> fetchRegistrationsMonthly([
    int months = 12,
  ]) async {
    final res = await _rpc(
      'admin_registrations_monthly',
      params: {'p_months': months},
    );
    return ((res as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> massBonus(int bonus) async {
    final res = await _rpc('admin_mass_bonus', params: {'bonus': bonus});
    return res as Map<String, dynamic>;
  }

  Future<int> resetAllPoints() async {
    final res = await _rpc('admin_reset_points');
    return (res as num).toInt();
  }

  Future<bool> togglePointsSystem(bool enabled) async {
    final res = await _rpc('admin_toggle_points', params: {'enabled': enabled});
    return res == true;
  }

  /// Ambil nominal pengaturan poin (untuk form admin).
  Future<Map<String, dynamic>> getPointSettings() async {
    final res = await _rpc('admin_get_point_settings').timeout(_openTimeout);
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Simpan nominal pengaturan poin. p = {key: value} (int atau string).
  Future<Map<String, dynamic>> updatePointSettings(
    Map<String, dynamic> p,
  ) async {
    final res = await _rpc('admin_update_point_settings', params: {'p': p});
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Feature flags (published per fitur) — untuk kartu Publish di panel admin.
  Future<Map<String, dynamic>> getFeatureFlags() async {
    final res = await _rpc('get_feature_flags').timeout(_openTimeout);
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Set flag publish satu fitur (tombol Publish). Return semua flags.
  Future<Map<String, dynamic>> setFeatureFlag(
    String feature,
    bool published,
  ) async {
    final res = await _rpc(
      'admin_set_feature_flag',
      params: {'p_feature': feature, 'p_published': published},
    );
    return res is Map ? Map<String, dynamic>.from(res) : {};
  }

  /// Katalog paket topup (admin) — untuk kelola harga/koin.
  Future<List<Map<String, dynamic>>> adminListTopupPackages() async {
    final res = await _rpc('list_topup_packages').timeout(_openTimeout);
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  /// Bypass privasi (toggle admin): bila ON, akun admin melihat semua
  /// field profil user tanpa filter visibility. Baca via getPointSettings
  /// (full app_settings). User biasa tidak terdampak (server cek email).
  Future<Map<String, dynamic>> setPrivacyBypass(bool enabled) async {
    final res = await _rpc(
      'admin_set_privacy_bypass',
      params: {'p_enabled': enabled},
    );
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
    final res = await _rpc(
      'admin_list_chats_page',
      params: {'p_limit': limit, 'p_offset': offset},
    );
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Ambil pesan chat dengan pagination (desc dari terbaru) — image_data
  /// kosong kecuali view-once. Foto biasa di-load lazy via PhotoCache.
  /// Timeout 30 dtk (seperti RPC buka-panel lain): tanpa ini koneksi stall
  /// membuat future tak pernah selesai → spinner monitor selamanya.
  Future<List<Map<String, dynamic>>> getChatMessages(
    String chatId, {
    int limit = 100,
    int offset = 0,
  }) async {
    final sw = Stopwatch()..start();
    final res = await _rpc(
      'admin_get_chat_messages_page',
      params: {'p_chat_id': chatId, 'p_limit': limit, 'p_offset': offset},
    ).timeout(_openTimeout);
    final list = res is List ? res : <dynamic>[];
    dlog(
      '[ADMIN-TIME] getChatMessages ${list.length} rows in ${sw.elapsedMilliseconds}ms '
      '(limit=$limit offset=$offset)',
    );
    return list.cast<Map<String, dynamic>>();
  }

  /// last_read_at chat (uid → timestamp mentah) untuk samakan centang-2
  /// monitor dengan chat asli. {} bila gagal.
  Future<Map<String, String>> getChatLastRead(String chatId) async {
    try {
      final res = await _rpc(
        'admin_get_chat_last_read',
        params: {'p_chat_id': chatId},
      ).timeout(_openTimeout);
      final map = res as Map<String, dynamic>?;
      if (map == null) return {};
      return map.map((k, v) => MapEntry(k.toString(), v.toString()));
    } catch (_) {
      return {};
    }
  }

  /// Fetch image_data satu foto (untuk retry / view-once admin).
  Future<String> getMessageImage(int messageId) async {
    final res = await _rpc(
      'admin_get_message_image',
      params: {'p_message_id': messageId},
    ).timeout(_openTimeout);
    return (res as String?) ?? '';
  }

  /// Hapus chat + (opsional) user. Return {'ok': bool, 'photo_paths': [...]}.
  Future<Map<String, dynamic>> deleteChat(
    String chatId,
    List<String> deleteUserIds,
  ) async {
    final res = await _rpc(
      'admin_delete_chat',
      params: {'p_chat_id': chatId, 'p_delete_user_ids': deleteUserIds},
    );
    return (res as Map<String, dynamic>?) ?? {};
  }

  /// Daftar call 1:1 yang sedang aktif (audio/video) — untuk badge monitor
  /// dan fitur pantau call di admin panel.
  Future<List<ActiveCallInfo>> getActiveCalls() async {
    final res = await _rpc('admin_active_calls').timeout(_openTimeout);
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
    final res = await _rpc('admin_sweep_calls');
    return (res as num?)?.toInt() ?? 0;
  }

  /// Daftar semua device semua user (pelacakan admin).
}
