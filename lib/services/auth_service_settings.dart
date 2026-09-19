part of 'auth_service.dart';

/// Domain **settings** AuthService (Fase 17) — dipisah dari file 1278 baris.
/// Satu library via `part`: field privat AuthService tetap bisa diakses,
/// interface `AuthService` tidak berubah (mock test aman).
mixin AuthServiceSettingsMx on AuthBase {
  /// Bersihkan akun anonymous stale (tidak aktif > 7 hari) di server.
  /// Agar nickname mereka bebas dipakai dan tidak muncul sebagai
  /// ghost "online". Fire-and-forget dari app saat start.
  Future<void> cleanupStaleAnonymous({int minAgeDays = 7}) async {
    try {
      await _sb.rpc(
        'cleanup_stale_anonymous',
        params: {'min_age_days': minAgeDays},
      );
    } catch (e) {
      dlog('[AUTH] cleanupStaleAnonymous error (abaikan): $e');
    }
  }

  /// Bersihkan presence room yang basi (> 10 menit) di server — row yang
  /// ditinggalkan app yang di-kill/force-stop tanpa sempat leaveRoom.
  /// Fire-and-forget dari app saat start.
  Future<void> cleanupStalePresence({int minAgeMinutes = 10}) async {
    try {
      await _sb.rpc(
        'cleanup_stale_presence',
        params: {'min_age_minutes': minAgeMinutes},
      );
    } catch (e) {
      dlog('[AUTH] cleanupStalePresence error (abaikan): $e');
    }
  }

  /// Ambil setting admin global: apakah screenshot aplikasi diizinkan.
  /// Default true (bisa screenshot) jika gagal / belum ada data.
  Future<bool> fetchScreenshotEnabled() async {
    try {
      final res = await _sb
          .from('app_settings')
          .select('screenshot_enabled')
          .eq('id', 'global')
          .maybeSingle();
      return res?['screenshot_enabled'] == true;
    } catch (e) {
      dlog('[AUTH] fetchScreenshotEnabled error: $e');
      return true;
    }
  }

  /// Update setting admin global. RLS membatasi hanya email admin (zunixe@gmail.com).
  Future<void> updateScreenshotEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'id': 'global',
      'screenshot_enabled': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// Polling row app_settings global — TIDAK memakai `.stream()`.
  ///
  /// `.stream()` (supabase 2.16.x) selalu `SELECT *` (lihat
  /// supabase_stream_builder.dart: `_queryBuilder.select()`), sementara
  /// `app_shared_secret` sengaja di-revoke dari anon/authenticated
  /// (20260915120000_security_hardening.sql). Akibatnya stream gagal
  /// `42501` dan `listenResilient` retry tanpa henti. Polling kolom
  /// eksplisit menghindari itu tanpa melonggarkan hardening.
  ///
  /// Interval 20 dtk: toggle admin tetap cepat sampai (dulu realtime
  /// instan; 20 dtk kompromi yang jauh lebih murah dari retry error
  /// terus-menerus).
  Stream<Map<String, dynamic>?> watchGlobalSettings() async* {
    yield await fetchGlobalSettings();
    yield* Stream<void>.periodic(const Duration(seconds: 20))
        .asyncMap((_) => fetchGlobalSettings());
  }

  /// Satu query ambil SEMUA setting global (pengganti 7× fetch terpisah
  /// saat boot — hemat 6 RPC per user). Return raw row (null bila gagal).
  ///
  /// Kolom EKSPLISIT (bukan `*`): `app_shared_secret` di-revoke dari anon/
  /// authenticated (hardening) — `select('*')` akan gagal permission.
  Future<Map<String, dynamic>?> fetchGlobalSettings() async {
    try {
      return await _sb
          .from('app_settings')
          .select(
            'screenshot_enabled,watermark_enabled,call_all_enabled,'
            'call_anon_enabled,reengage_enabled,require_registration,'
            'app_font_family,invisible_enabled,invisible_admin_uid',
          )
          .eq('id', 'global')
          .maybeSingle();
    } catch (e) {
      dlog('[AUTH] fetchGlobalSettings error: $e');
      return null;
    }
  }

  /// Setting admin: tombol call tampil ke SEMUA user (termasuk anon/guest).
  /// Default false = hanya user terdaftar yang melihat tombol call.
  Future<bool> fetchCallAllEnabled() async {
    try {
      final res = await _sb
          .from('app_settings')
          .select('call_all_enabled')
          .eq('id', 'global')
          .maybeSingle();
      return res?['call_all_enabled'] == true;
    } catch (e) {
      dlog('[AUTH] fetchCallAllEnabled error: $e');
      return false;
    }
  }

  /// Update setting admin global: satu toggle call untuk semua user.
  /// Menulis kedua kolom sekaligus supaya tombol tampil (call_all) dan
  /// izin anon/dummy (call_anon, ditegakkan RLS calls_insert) selalu sinkron.
  /// RLS membatasi hanya email admin (zunixe@gmail.com).
  Future<void> updateCallEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'id': 'global',
      'call_all_enabled': enabled,
      'call_anon_enabled': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// Setting admin: anon & dummy boleh call. Default false = hanya
  /// user terdaftar (+ admin) yang bisa menelepon (anti spam/griefing).
  Future<bool> fetchCallAnonEnabled() async {
    try {
      final res = await _sb
          .from('app_settings')
          .select('call_anon_enabled')
          .eq('id', 'global')
          .maybeSingle();
      return res?['call_anon_enabled'] == true;
    } catch (e) {
      dlog('[AUTH] fetchCallAnonEnabled error: $e');
      return false;
    }
  }

  /// Ambil setting admin global: apakah foto view-once di-watermark forensik.
  /// Default false (kirim biasa) jika gagal / belum ada data.
  Future<bool> fetchWatermarkEnabled() async {
    try {
      final res = await _sb
          .from('app_settings')
          .select('watermark_enabled')
          .eq('id', 'global')
          .maybeSingle();
      return res?['watermark_enabled'] == true;
    } catch (e) {
      dlog('[AUTH] fetchWatermarkEnabled error: $e');
      return false;
    }
  }

  /// Update setting admin global. RLS membatasi hanya email admin (zunixe@gmail.com).
  Future<void> updateWatermarkEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'id': 'global',
      'watermark_enabled': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// Ambil setting admin: invisible (admin tidak muncul di daftar online).
  /// Return Map {'enabled': bool, 'adminUid': String?}.
  Future<Map<String, dynamic>> fetchInvisibleSetting() async {
    try {
      final res = await _sb
          .from('app_settings')
          .select('invisible_enabled,invisible_admin_uid')
          .eq('id', 'global')
          .maybeSingle();
      return {
        'enabled': res?['invisible_enabled'] == true,
        'adminUid': res?['invisible_admin_uid'] as String?,
      };
    } catch (e) {
      dlog('[AUTH] fetchInvisibleSetting error: $e');
      return {'enabled': false, 'adminUid': null};
    }
  }

  /// Update setting admin invisible. RLS membatasi hanya admin.
  /// Saat enabled=true, simpan UID admin supaya trigger server bisa
  /// memaksa status 'invisible' pada user itu.
  Future<void> updateInvisibleEnabled(bool enabled) async {
    final myUid = uid;
    await _sb.from('app_settings').upsert({
      'id': 'global',
      'invisible_enabled': enabled,
      'invisible_admin_uid': enabled ? myUid : null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// Ambil setting admin global: apakah wajib registrasi sebelum masuk.
  /// Default false (bisa mulai chat tanpa daftar) jika gagal / belum ada data.
  Future<bool> fetchRequireRegistration() async {
    try {
      final res = await _sb
          .from('app_settings')
          .select('require_registration')
          .eq('id', 'global')
          .maybeSingle();
      return res?['require_registration'] == true;
    } catch (e) {
      dlog('[AUTH] fetchRequireRegistration error: $e');
      return false;
    }
  }

  /// Update setting admin global. RLS membatasi hanya admin.
  Future<void> updateRequireRegistration(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'id': 'global',
      'require_registration': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// Daftar install_id yang di-exclude dari ringkasan & daftar perangkat.
  /// RPC admin — RLS guard zunixe@gmail.com.
  Future<List<String>> fetchExcludedDevices() async {
    try {
      final res = await _sb.rpc('admin_get_excluded_devices');
      if (res is List) {
        return res.map((e) => '$e').where((s) => s.isNotEmpty).toList();
      }
      return [];
    } catch (e) {
      dlog('[AUTH] fetchExcludedDevices error: $e');
      return [];
    }
  }

  /// Simpan daftar install_id yang di-exclude. RPC menghapus cache stats
  /// supaya ringkasan langsung segar.
  Future<bool> updateExcludedDevices(List<String> installIds) async {
    try {
      final res = await _sb.rpc(
        'admin_set_excluded_devices',
        params: {'p_list': installIds},
      );
      return res is List;
    } catch (e) {
      dlog('[AUTH] updateExcludedDevices error: $e');
      return false;
    }
  }

  /// Exclude SATU perangkat + cascade: semua uid yang pernah login di device
  /// itu ikut ditambahkan ke `excluded_uids`. Penting karena `install_id`
  /// (ANDROID_ID) bisa BERUBAH untuk HP yang sama (Android 8+ meng-scope ke
  /// user profile + signing key) — tanpa cascade, device ter-exclude
  /// "muncul lagi" sebagai device baru. Return daftar terbaru
  /// (device + uid) bila sukses, null bila gagal.
  Future<({List<String> devices, List<String> uids})?> excludeDeviceCascade(
    String installId,
  ) async {
    try {
      final res = await _sb.rpc(
        'admin_exclude_device_cascade',
        params: {'p_install_id': installId},
      );
      if (res is! Map) return null;
      List<String> strList(dynamic v) =>
          v is List ? v.map((e) => '$e').where((s) => s.isNotEmpty).toList() : [];
      return (
        devices: strList(res['devices']),
        uids: strList(res['uids']),
      );
    } catch (e) {
      dlog('[AUTH] excludeDeviceCascade error: $e');
      return null;
    }
  }

  /// Ambil font global aplikasi (key katalog AppFonts). Default 'default'.
  Future<String> fetchAppFontFamily() async {
    try {
      final res = await _sb
          .from('app_settings')
          .select('app_font_family')
          .eq('id', 'global')
          .maybeSingle();
      final v = res?['app_font_family'] as String?;
      return (v == null || v.isEmpty) ? 'default' : v;
    } catch (e) {
      dlog('[AUTH] fetchAppFontFamily error: $e');
      return 'default';
    }
  }

  /// Update font global aplikasi. RLS membatasi hanya admin.
  Future<void> updateAppFontFamily(String key) async {
    await _sb.from('app_settings').upsert({
      'id': 'global',
      'app_font_family': key,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// Ambil toggle notifikasi pengingat harian (re-engagement) — admin global.
  Future<bool> fetchReengageEnabled() async {
    try {
      final res = await _sb
          .from('app_settings')
          .select('reengage_enabled')
          .eq('id', 'global')
          .maybeSingle();
      return res?['reengage_enabled'] != false;
    } catch (e) {
      dlog('[AUTH] fetchReengageEnabled error: $e');
      return true;
    }
  }

  /// Update toggle pengingat harian. RLS membatasi hanya admin.
  Future<void> updateReengageEnabled(bool enabled) async {
    await _sb.from('app_settings').upsert({
      'id': 'global',
      'reengage_enabled': enabled,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  /// Stream perubahan setting app_settings (realtime) — dipakai AuthProvider
  /// supaya toggle admin langsung berdampak di semua device tanpa polling.
  Stream<Map<String, dynamic>> onAppSettingsUpdated() {
    final channel = _sb.channel('auth-app-settings');
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'app_settings',
      callback: (payload) {
        controller.add(Map<String, dynamic>.from(payload.newRecord));
      },
    );
    channel.subscribe();
    controller.onCancel = () => _sb.removeChannel(channel);
    return controller.stream;
  }
}
