part of 'auth_provider.dart';

mixin _AuthSettingsMx on _AuthBase {
  Future<void> _loadGlobalSettings() async {
    final row = await _auth.fetchGlobalSettings();
    if (row == null) {
      _emit();
      return;
    }
    _screenshotEnabled = row['screenshot_enabled'] == true;
    ScreenSecureService.setScreenshotEnabled(_screenshotEnabled);
    _callAllEnabled = row['call_all_enabled'] == true;
    _callAnonEnabled = row['call_anon_enabled'] == true;
    _reengageEnabled = row['reengage_enabled'] != false;
    _watermarkEnabled = row['watermark_enabled'] == true;
    _requireRegistration = row['require_registration'] == true;
    _applyAppFont(row['app_font_family'] as String?);
    final invisibleOn =
        row['invisible_enabled'] == true &&
        row['invisible_admin_uid'] == _auth.uid;
    _invisibleEnabled = invisibleOn;
    if (invisibleOn) {
      _profile = _profile?.copyWith(status: 'invisible');
      safeUnawaited(_auth.goInvisible());
    }
    _emit();
  }

  /// Admin: toggle notifikasi pengingat harian (19:00 WIB, user offline).
  Future<void> setReengageEnabled(bool enabled) async {
    _reengageEnabled = enabled;
    _emit();
    try {
      await _auth.updateReengageEnabled(enabled);
    } catch (e) {
      dlog('[AUTH] updateReengageEnabled error: $e');
    }
  }

  /// Admin: call untuk semua user. Satu toggle menulis kedua flag
  /// (tampil tombol + izin anon/dummy) supaya selalu sinkron.
  Future<void> setCallEnabled(bool enabled) async {
    _callAllEnabled = enabled;
    _callAnonEnabled = enabled;
    _emit();
    try {
      await _auth.updateCallEnabled(enabled);
    } catch (e) {
      dlog('[AUTH] updateCallEnabled error: $e');
    }
  }

  /// Admin mengubah izin screenshot aplikasi (disimpan di server, semua device kena).
  Future<void> setScreenshotEnabled(bool enabled) async {
    _screenshotEnabled = enabled;
    ScreenSecureService.setScreenshotEnabled(enabled);
    _emit();
    try {
      await _auth.updateScreenshotEnabled(enabled);
    } catch (e) {
      dlog('[AUTH] updateScreenshotEnabled error: $e');
    }
  }

  /// Admin mengaktifkan/menonaktifkan watermark forensik foto view-once.
  Future<void> setWatermarkEnabled(bool enabled) async {
    _watermarkEnabled = enabled;
    _emit();
    try {
      await _auth.updateWatermarkEnabled(enabled);
    } catch (e) {
      dlog('[AUTH] updateWatermarkEnabled error: $e');
    }
  }

  /// Ambil setting admin global (invisible — tidak muncul di daftar online).
  /// Hanya admin dengan UID yang tercatat yang ikut jadi invisible.
  /// (Dipanggil dari _loadGlobalSettings + resyncInvisible saat resume.)

  /// Re-sync setting invisible (dipanggil saat app resumed). Supaya device
  /// kedua ikut tahu toggle dari device pertama dan tidak menimpa balik.
  Future<void> resyncInvisible() async {
    final setting = await _auth.fetchInvisibleSetting();
    final enabled =
        setting['enabled'] == true && setting['adminUid'] == _auth.uid;
    if (enabled == _invisibleEnabled) return;
    _invisibleEnabled = enabled;
    if (enabled) {
      _idleTimer?.cancel();
      _isIdle = false;
      await _auth.goInvisible();
      _profile = _profile?.copyWith(status: 'invisible');
    }
    _emit();
  }

  /// Admin toggle invisible. ON → status invisible (user lain lihat offline,
  /// tidak muncul di daftar online; admin sendiri lihat "invisible").
  /// OFF → kembali online. Hanya tersedia untuk admin.
  Future<void> setInvisibleEnabled(bool enabled) async {
    _invisibleEnabled = enabled;
    _emit();
    try {
      await _auth.updateInvisibleEnabled(enabled);
      if (enabled) {
        _idleTimer?.cancel();
        _isIdle = false;
        await _auth.goInvisible();
        _profile = _profile?.copyWith(status: 'invisible');
        safeUnawaited(RealtimeHub.instance.untrackOnline());
      } else {
        await _auth.goOnline();
        _profile = _profile?.copyWith(status: 'online');
        resetIdleTimer();
        safeUnawaited(_updateLocationOnOnline());
        if (uid != null)
          safeUnawaited(
            RealtimeHub.instance.trackOnline(uid!, _profile?.nickname ?? ''),
          );
      }
    } catch (e) {
      dlog('[AUTH] updateInvisibleEnabled error: $e');
    }
    _emit();
  }

  /// Bersihkan akun anonymous stale di server (fire-and-forget).
  Future<void> cleanupStaleAnonymous({int minAgeDays = 7}) {
    return _auth.cleanupStaleAnonymous(minAgeDays: minAgeDays);
  }

  /// Ambil daftar device ter-exclude (admin-only) — hanya untuk sesi
  /// admin sungguhan; user/dummy tidak perlu datanya.
  Future<void> _loadExcludedDevices() async {
    if (!isRealAdmin) return;
    _excludedDevices = await _auth.fetchExcludedDevices();
    _emit();
  }

  /// Simpan daftar device ter-exclude (admin-only), lalu refresh daftar
  /// perangkat supaya item ter-exclude langsung hilang dari tab Perangkat.
  Future<bool> setExcludedDevices(List<String> installIds) async {
    final ok = await _auth.updateExcludedDevices(installIds);
    if (ok && !_disposed) {
      _excludedDevices = List.of(installIds);
      _emit();
    }
    return ok;
  }

  /// Exclude satu perangkat lewat RPC cascade (device + semua uid-nya).
  /// Dipakai tombol "Exclude perangkat ini" supaya exclude tahan walau
  /// `install_id` berubah (Android ID ter-scope ke signing key).
  Future<bool> excludeDeviceCascade(String installId) async {
    if (installId.isEmpty) return false;
    final res = await _auth.excludeDeviceCascade(installId);
    if (res == null) return false;
    if (!_disposed) {
      _excludedDevices = res.devices;
      _emit();
    }
    return true;
  }

  /// Admin toggle wajib registrasi. Realtime: semua device ikut update
  /// lewat subscription app_settings (tidak perlu polling).
  Future<void> setRequireRegistration(bool enabled) async {
    _requireRegistration = enabled;
    _emit();
    try {
      await _auth.updateRequireRegistration(enabled);
    } catch (e) {
      dlog('[AUTH] updateRequireRegistration error: $e');
    }
  }

  /// Terapkan font global (key katalog AppFonts): set static + persist prefs,
  /// increment revisi tema. Return true bila berubah (pemanggil notify).
  bool _applyAppFont(String? key) {
    final next = AppFonts.resolve(key);
    if (next == _appFontFamily) return false;
    _appFontFamily = next;
    AppFonts.setLocal(next);
    AppTheme.fontRevision++;
    // Persist supaya frame pertama restart pakai font yang sama.
    SharedPreferences.getInstance().then(
      (p) => p.setString(AppFonts.prefKey, next),
    );
    return true;
  }

  /// Admin: ganti font global aplikasi. Update lokal instan + upsert server
  /// (realtime menyebar ke semua device).
  Future<void> setAppFontFamily(String key) async {
    final changed = _applyAppFont(key);
    if (changed) _emit();
    try {
      await _auth.updateAppFontFamily(AppFonts.resolve(key));
    } catch (e) {
      dlog('[AUTH] updateAppFontFamily error: $e');
    }
  }

  /// Subscribe realtime app_settings — toggle admin langsung berdampak di
  /// semua device (mis. wajib registrasi, screenshot, watermark, invisible).
  /// Realtime setting global via .stream() — pola yang sama (dan terbukti
  /// jalan) dengan toggle Sistem Poin di PointsProvider.watchEnabled().
  /// Resilient: error channel me-restart subscription otomatis (dulu:
  /// mati permanen → toggle admin tidak berefek sampai restart).
  void _listenAppSettings() {
    if (_appSettingsSub != null) return;
    _appSettingsSub = listenResilient<Map<String, dynamic>?>(
      () => _auth.watchGlobalSettings(),
      (row) {
        if (_disposed) return;
        if (row == null) return;
        dlog(
          '[SETTINGS] row call_all_enabled='
          '${row['call_all_enabled']} '
          'call_anon_enabled=${row['call_anon_enabled']} '
          'require_registration=${row['require_registration']}',
        );
        var changed = false;
        final nextCall = row['call_all_enabled'] == true;
        if (nextCall != _callAllEnabled) {
          _callAllEnabled = nextCall;
          changed = true;
        }
        final nextAnon = row['call_anon_enabled'] == true;
        if (nextAnon != _callAnonEnabled) {
          _callAnonEnabled = nextAnon;
          changed = true;
        }
        final nextReq = row['require_registration'] == true;
        if (nextReq != _requireRegistration) {
          _requireRegistration = nextReq;
          changed = true;
        }
        if (_applyAppFont(row['app_font_family'] as String?)) changed = true;
        if (changed) _emit();
      },
      isDisposed: () => _disposed,
      onError: (e) => dlog('[SETTINGS] stream error: $e'),
    );
  }

  /// Polling cadangan bila websocket realtime mati — 15 menit (realtime
  /// tetap jalur utama; dulu 5 mnt, dijarangkan lagi supaya hemat RPC
  /// per user — realtime app_settings sudah menutup perubahan instan).
  void _startSettingsPolling() {
    _settingsPollTimer?.cancel();
    _settingsPollTimer = Timer.periodic(const Duration(minutes: 15), (_) async {
      if (_disposed || !_auth.isSignedIn) return;
      try {
        final row = await _auth.fetchGlobalSettings();
        if (row == null) return;
        var changed = false;
        final callAll = row['call_all_enabled'] == true;
        if (callAll != _callAllEnabled) {
          _callAllEnabled = callAll;
          changed = true;
        }
        final callAnon = row['call_anon_enabled'] == true;
        if (callAnon != _callAnonEnabled) {
          _callAnonEnabled = callAnon;
          changed = true;
        }
        final reqReg = row['require_registration'] == true;
        if (reqReg != _requireRegistration) {
          _requireRegistration = reqReg;
          changed = true;
        }
        if (_applyAppFont(row['app_font_family'] as String?)) changed = true;
        // Sinkron daftar device ter-exclude (admin-only).
        if (isRealAdmin) {
          final excl = await _auth.fetchExcludedDevices();
          final same =
              excl.length == _excludedDevices.length &&
              excl.every(_excludedDevices.contains);
          if (!same) {
            _excludedDevices = excl;
            changed = true;
          }
        }
        if (changed) _emit();
      } catch (e) {
        dlog('[SETTINGS-POLL] error: $e');
      }
    });
  }

  /// Ambil profil user lain by UID.
  Future<UserModel?> getOtherProfile(String uid) => _auth.getProfileById(uid);

  /// Profil user lain dari cache SQLite (SINKRON) — untuk frame pertama tanpa
  /// "keload dulu". null bila belum pernah di-cache di sesi ini.
  UserModel? peekProfileCache(String uid) => _auth.peekProfileCache(uid);

  /// Preload cache profil user lain ke memori.
  Future<void> preloadProfileCache(String uid) =>
      _auth.preloadProfileCache(uid);

  /// Resolve PATH avatar → base64 (RAM → disk → network). Dipisah dari
  /// [getOtherProfile] supaya lambatnya/gagalnya avatar tidak menahan
  /// tampilnya profil.
  Future<String> getAvatarByPath(String path) => _auth.getAvatarByPath(path);

  /// Peek SINKRON avatar dari cache RAM (tanpa network) — dipakai UI supaya
  /// foto yang sudah dimuat di daftar/header chat langsung tampil pada frame
  /// pertama halaman profil (anti-kedip). Null bila belum ada di RAM.
  String? cachedAvatarSync(String uid) =>
      AvatarB64Service.instance.cachedSync(uid);

  /// Peek SINKRON RAM lalu disk — untuk halaman profil tunggal supaya cold
  /// start tetap instan (anti-kedip) tanpa menunggu network.
  String? cachedAvatarSyncDeep(String uid) =>
      AvatarB64Service.instance.cachedSyncIncludeDisk(uid);

  /// Sign up dengan email — membuat akun Supabase baru (butuh verifikasi
  /// email). Return true bila session sudah aktif (auto-confirm), false bila
  /// perlu verifikasi OTP dulu.
}
