part of 'auth_provider.dart';

mixin _AuthInitMx on _AuthBase {
  AuthData build() {
    ref.onDispose(_disposeAll);
    if (!_autoInit) return const AuthData(loading: false);
    dlog('[AUTH-PROVIDER] CONSTRUCTED $instanceId');
    _listenAuthState();
    _init();
    loadNotificationPref();
    _loadPendingReferrer();
    return const AuthData();
  }

  void _emit() {
    if (_disposed) return;
    final email = _auth.currentUser?.email;
    final admin = AdminGate.isRealAdmin(email);
    state = AuthData(
      profile: _profile,
      loading: _loading,
      error: _error,
      signingOut: _signingOut,
      uid: _auth.uid,
      isSignedIn: _auth.isSignedIn,
      isAnonymous: _auth.isAnonymous,
      dummySessionActive: _auth.dummySessionActive,
      emailConfirmed: _auth.emailConfirmed,
      userEmail: _auth.userEmail,
      hasPassword: _auth.hasPassword,
      isRealAdmin: admin,
      anonBlocked:
          _requireRegistration &&
          _auth.isAnonymous &&
          !_auth.dummySessionActive,
      anonTimelineBlocked:
          _auth.isAnonymous && !_auth.dummySessionActive && !admin,
      screenshotEnabled: _screenshotEnabled,
      watermarkEnabled: _watermarkEnabled,
      invisibleEnabled: _invisibleEnabled,
      reengageEnabled: _reengageEnabled,
      requireRegistration: _requireRegistration,
      callAllEnabled: _callAllEnabled,
      callAnonEnabled: _callAnonEnabled,
      appFontFamily: _appFontFamily,
      excludedDevices: List.unmodifiable(_excludedDevices),
      notificationsEnabled: _notificationsEnabled,
    );
  }

  /// Seed profil untuk pengujian jalur kirim (tanpa login sungguhan).
  /// Dipakai test yang butuh melewati guard `profile == null`.
  @visibleForTesting
  void seedProfileForTest(UserModel p) {
    _profile = p;
    _loading = false;
    _emit();
  }

  /// Baca referrer tersimpan (dari deep link) ke memori.
  Future<void> _loadPendingReferrer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _pendingReferrer = prefs.getString(_referrerPrefKey);
    } catch (_) {}
  }

  /// Simpan referrer (dipanggil saat deep link referal masuk).
  Future<void> setPendingReferrer(String uid) async {
    if (uid.isEmpty) return;
    _pendingReferrer = uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_referrerPrefKey, uid);
    } catch (_) {}
  }

  /// Ikat referrer (sekali) & klaim reward untuk pengundang. Fire-and-forget.
  Future<void> _bindAndClaimReferrer() async {
    final referrer = _pendingReferrer;
    if (referrer == null || referrer.isEmpty) return;
    _pendingReferrer = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_referrerPrefKey);
    } catch (_) {}
    // Faucet referral DIHAPUS (overhaul coin: tidak ada poin gratis).
  }

  /// Sinkron identitas user ke TikTok App Events (identify) + kirim event.
  /// Best-effort: tidak pernah menggagalkan alur auth. Dipanggil tiap
  /// login/daftar & saat profil berubah (panduan TikTok: identify saat
  /// info user berubah).
  void _syncTikTok({TikTokEvent? event}) {
    final p = _profile;
    final id = p?.uid.isNotEmpty == true ? p!.uid : (_auth.uid ?? '');
    if (id.isEmpty) return;
    safeUnawaited(() async {
      try {
        await TikTokService.instance.identify(
          externalId: id,
          externalUserName: p?.nickname ?? '',
          phoneNumber: p?.phone ?? '',
          email: p?.email ?? '',
        );
        if (event != null) await TikTokService.instance.track(event);
      } catch (_) {}
    }());
  }

  /// Pantau event auth Supabase. Kalau session hilang TANPA logout manual
  /// (mis. user anon dihapus di server / refresh token gagal), reset profile
  /// lokal agar tidak jadi "zombie" (user ID kosong & tidak online).
  void _listenAuthState() {
    _authStateSub = _auth.authStateChanges.listen(
      (state) async {
        if (_disposed) return;
        // Safety-net: email baru saja terkonfirmasi (link OTP / deep link)
        // → sinkronkan is_registered + email ke profiles. Tanpa ini akun yang
        // mengonfirmasi belakangan tetap tercatat anon di admin panel.
        if ((state.event == AuthChangeEvent.signedIn ||
                state.event == AuthChangeEvent.userUpdated) &&
            (_auth.currentUser?.emailConfirmedAt != null)) {
          final p = _profile;
          if (p == null || !p.isRegistered) {
            await _auth.markRegistered();
            _profile = await _auth.getProfile();
            _emit();
          }
        }
        if (state.event != AuthChangeEvent.signedOut) return;
        if (_manualSignOut) return; // logout manual — sudah di-handle signOut()
        // Sesi dummy bisa mati di server (admin_renew_dummy_token menghapus
        // SEMUA session dummy, termasuk yang aktif di HP ini). Kalau token
        // admin masih tersimpan, pulihkan otomatis — jangan langsung reset.
        final canRecoverDummy =
            AdminGate.backToAdminImpl != null &&
            (dummySessionActive ||
                (AdminGate.hasStoredDummyTokens != null &&
                    await AdminGate.hasStoredDummyTokens!()));
        if (canRecoverDummy) {
          try {
            final restored = await AdminGate.backToAdminImpl!();
            if (restored && !_disposed) {
              dlog('[AUTH] signedOut tapi admin dipulihkan, re-init');
              await _init();
              return;
            }
          } catch (e) {
            dlog('[AUTH] signedOut recovery error: $e');
          }
        }
        dlog(
          '[AUTH] SIGNED_OUT unexpected, resetting profile (session hilang)',
        );
        _idleTimer?.cancel();
        _heartbeatTimer?.cancel();
        _locationTimer?.cancel();
        _profileSub?.cancel();
        _isIdle = false;
        _profile = null;
        // Safety-net logout paksa (sesi kedaluwarsa/kick server): tutup
        // stream & channel chat milik user lama — logout manual sudah
        // menangani via ChatProvider.reset() di ProfileScreen.
        _onSignedOut?.call();
        _emit();
      },
      onError: (e) {
        dlog('[AUTH] authState stream error: $e');
      },
    );
  }

  /// Hook opsional: dipasang root widget untuk membersihkan resource
  /// chat saat signedOut TIDAK lewat tombol logout (sesi mati).
  void Function()? _onSignedOut;
  set onSignedOut(void Function()? cb) => _onSignedOut = cb;

  /// Cache profil sendiri (SharedPreferences): cold start dengan sesi
  /// existing langsung tampil MainNav dari disk, revalidasi network di
  /// belakang. Key per-uid supaya ganti akun tidak tertukar.

  Future<UserModel?> _loadCachedProfile() async {
    try {
      final uid = _auth.currentUser?.id;
      if (uid == null || uid.isEmpty) return null;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_profileCachePrefix$uid');
      if (raw == null || raw.isEmpty) return null;
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return UserModel.fromMap(uid, map);
    } catch (_) {
      return null; // corrupt → abaikan, jalur network normal
    }
  }

  Future<void> _saveCachedProfile(UserModel p) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_profileCachePrefix${p.uid}',
        jsonEncode(p.toMap()),
      );
    } catch (_) {}
  }

  Future<void> _init() async {
    if (_initInProgress) return; // guard re-entry
    _initInProgress = true;
    dlog('[AUTH] _init start');
    _loading = true;
    _error = null;
    // Login/restore baru: transisi keluar sudah selesai.
    _signingOut = false;
    _emit();
    // Auto-retry dengan backoff: jaringan (DNS/connectivity) sering gagal
    // sesaat, apalagi pas baru connect WiFi atau ganti user. Jangan langsung
    // tampilkan layar error — coba ulang dulu beberapa kali.
    // Optimasi jutaan user: jika session sudah ada (restore), jangan signInAnonymously lagi
    final hasSession = _auth.currentUser != null;
    // Profil cache: tampilkan MainNav langsung dari disk saat sesi ada,
    // revalidasi network di belakang. Hemat 0.7-1.7s RPC getProfile.
    // Stale-while-revalidate: kalau network gagal total tapi cache ada,
    // tetap tampil konten (jangan layar error).
    if (hasSession) {
      final cached = await _loadCachedProfile();
      if (cached != null && !_disposed) {
        _profile = cached;
        _loading = false;
        _emit();
      }
    }
    final maxAttempts = hasSession ? 1 : 2;
    const delays = [2, 3];
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        dlog(
          '[AUTH] _init attempt $attempt/$maxAttempts hasSession=$hasSession',
        );
        // TANPA auto signInAnonymously: user TIDAK dibuat otomatis. Bila belum
        // ada sesi, gate menampilkan EntryScreen — sesi anon + profil baru
        // dibuat SAAT user menekan "Mulai" (registerProfile membuat anon
        // session dgn nickname PILIHAN user, bukan 'AnonXXXX').
        // Ini mencegah baris 'AnonXXXX' hantu untuk user yang cuma buka app.
        if (!hasSession) {
          _profile = null;
          _loading = false;
          _emit();
          // EntryScreen butuh setting global (mis. require_registration) —
          // muat tanpa sesi (fire-and-forget, tak menahan UI).
          _loadGlobalSettings().catchError(
            (e) => dlog('[AUTH] globalSettings (no-session) error: $e'),
          );
          _listenAppSettings();
          safeUnawaited(_loadExcludedDevices());
          _initInProgress = false;
          return;
        }
        // Satu fetch saja (tanpa avatar) → langsung notify, UI tidak nunggu
        // foto. Dulu ada SELECT ke-2 (full avatar) — kini avatar di-resolve
        // lazy dari cache disk/RAM via AvatarB64Service, tanpa SELECT ulang.
        _profile = await _auth.getProfile(withAvatar: false);
        dlog('[AUTH] getProfile lite -> ${_profile?.uid}');
        // ── Sinkronisasi flag dummy vs sesi nyata (anti "setengah admin") ──
        // Recovery backToAdmin yang gagal bisa meninggalkan flag dummy true
        // padahal sesi sekarang = akun admin asli. Email admin ≠ dummy →
        // flag basi, bersihkan di sini (satu titik, jalan tiap login/init).
        if (_auth.dummySessionActive &&
            _profile?.email == AdminGate.adminEmail) {
          dlog('[AUTH] dummy flag stale (sesi=admin) — dibersihkan');
          _auth.markDummyState(active: false);
        }
        if (_profile != null) {
          safeUnawaited(_saveCachedProfile(_profile!));
          // Akun banned: paksa offline supaya hilang dari daftar online.
          if (isProfileBanned) safeUnawaited(_auth.goOffline());
          _emit();
          // Welcome bonus ANON (100 coin) — sekali per install_id device.
          // Hanya untuk sesi anon nyata (bukan admin/dummy).
          if ((_profile?.isRegistered == false) && !_auth.dummySessionActive) {
            safeUnawaited(_claimWelcome('anon'));
          }
        }
        // Avatar lazy: path storage → base64 via AvatarB64Service (disk
        // first, network hanya saat miss). Fire-and-forget — boot tidak
        // menunggu download avatar, dan TANPA SELECT profil kedua.
        final p0 = _profile;
        if (p0 != null &&
            p0.avatar.isNotEmpty &&
            StoragePhotoService.instance.isAvatarPath(p0.avatar)) {
          AvatarB64Service.instance.getByPath(p0.avatar).then((b64) {
            if (!_disposed && b64.isNotEmpty) {
              final p = _profile;
              if (p != null) {
                _profile = p.copyWith(avatar: b64);
                safeUnawaited(_saveCachedProfile(_profile!));
                _emit();
              }
            }
          });
        }
        await AdminGate.restoreDummySession?.call();
        _listenProfile();
        // Satu query ambil SEMUA setting global (pengganti 7× fetch
        // sequential) → split di memori. Fire-and-forget: entry screen
        // hanya pakai require_registration untuk sembunyikan kartu anon —
        // boleh menyusul, jangan tahan loading.
        _loadGlobalSettings().catchError(
          (e) => dlog('[AUTH] globalSettings error: $e'),
        );
        safeUnawaited(_loadExcludedDevices());
        _listenAppSettings();
        _startSettingsPolling();
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        dlog('[AUTH] _init attempt $attempt failed: $e');
        if (_disposed) return;
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: delays[attempt - 1]));
          if (_disposed) return;
        }
      }
    }
    if (lastError != null) {
      dlog('[AUTH] _init ERROR: $lastError');
      // Cache ada → tetap tampil konten lama, jangan layar error.
      if (_profile == null) {
        _error = lastError.toString();
      }
    } else {
      // FCM token & cleanup di-fire-and-forget — tidak block loading screen
      if (_profile != null) {
        safeUnawaited(refreshHasPassword());
        safeUnawaited(updateFcmToken());
        // Catat identitas perangkat + install ID untuk pelacakan admin.
        // Hanya saat user SUDAH punya profil — anon fresh tanpa profil akan
        // kena FK violation (user_id belum ada di profiles).
        safeUnawaited(DeviceInfoService.instance.syncToServer());
      }
      safeUnawaited(cleanupStaleAnonymous());
      safeUnawaited(cleanupStalePresence());
      if (_disposed) return;
      _startHeartbeat();
      // Lokasi lazy 2 detik setelah UI tampil — hemat 2-5 detik TTI, tidak block cold start untuk jutaan user
      Future.delayed(const Duration(seconds: 2), () {
        if (_disposed) return;
        _startLocationPing();
        safeUnawaited(_initLocation());
      });
      if (_profile != null &&
          !_invisibleEnabled &&
          !_isIdle &&
          !isProfileBanned &&
          uid != null) {
        safeUnawaited(
          RealtimeHub.instance.trackOnline(uid!, _profile!.nickname),
        );
      }
      // Daily login bonus poin
      safeUnawaited(_claimDailyPoints());
    }
    _loading = false;
    _initInProgress = false;
    _emit();
    dlog('[AUTH] _init done loading=false');
  }

  /// Login anonim (fallback saat session hilang).
  /// Setelah login, ambil profile jika sudah ada.
  Future<void> signInAnonymously() async {
    await _auth.signInAnonymously();
    _profile = await _auth.getProfile();
    _listenProfile();
    _restartPresenceTimers();
    // Daftarkan device agar anon dari HP ter-exclude ikut tersaring di
    // ringkasan admin (hanya bila profil sudah ada — cegah FK violation).
    if (_profile != null) {
      safeUnawaited(DeviceInfoService.instance.syncToServer());
    }
    _emit();
  }

  /// Login dengan Google SSO via Supabase.
  /// Return:
  ///   'linked'  — email sudah ada di akun lain, profile berhasil di-link
  ///   'linked_existing' — email sudah ada, tapi user menolak linking (tetap pakai akun baru)
  ///   'new'     — user baru, perlu isi profile
  ///   'exists'  — profile sudah ada (login ulang)
  Future<String> signInWithGoogle() async {
    _manualSignOut = true;
    final ({AuthResponse response, String? googleEmail})? result;
    try {
      result = await _auth.signInWithGoogle();
    } finally {
      _manualSignOut = false;
    }
    // User membatalkan dialog Google — tanpa pesan error.
    if (result == null) return 'canceled';
    final googleEmail = result.googleEmail;

    // Bersihkan semua cache lama setelah login Google (DB + gambar —
    // akun bisa berganti pemilik, foto user lama tidak boleh tersisa).
    MessageCache.instance.clearAllLegacy().catchError((_) {});
    ImageCacheHygiene.clearAll();

    // Cek apakah email ini sudah punya profile di akun lain
    if (googleEmail != null) {
      final existing = await _auth.checkEmailExists(googleEmail);
      if (existing != null) {
        _pendingLinkProfileId = existing['profile_id'] as String?;
        _pendingLinkNickname = existing['nickname'] as String?;
        _profile = await _auth.getProfile();
        _listenProfile();
        _restartPresenceTimers();
        safeUnawaited(DeviceInfoService.instance.syncToServer());
        safeUnawaited(updateFcmToken());
        _emit();
        return 'link_prompt';
      }
    }

    _profile = await _auth.getProfile();
    _listenProfile();
    _restartPresenceTimers();
    safeUnawaited(DeviceInfoService.instance.syncToServer());
    safeUnawaited(updateFcmToken());
    // User Google yang sudah punya profil = login ulang → event LOGIN.
    if (_profile != null) _syncTikTok(event: TikTokEvent.LOGIN);
    _emit();
    if (_profile != null) return 'exists';
    return 'new';
  }

  String? _pendingLinkProfileId;
  String? _pendingLinkNickname;

  String? get pendingLinkNickname => _pendingLinkNickname;

  /// Konfirmasi linking — pindahkan profile lama ke akun Google baru
  Future<void> confirmLinkGoogle() async {
    if (_pendingLinkProfileId == null) return;
    await _auth.linkGoogleProfile(_pendingLinkProfileId!);
    _profile = await _auth.getProfile();
    _listenProfile();
    _pendingLinkProfileId = null;
    _pendingLinkNickname = null;
    safeUnawaited(DeviceInfoService.instance.syncToServer());
    safeUnawaited(updateFcmToken());
    _emit();
  }

  /// Tolak linking — tetap pakai akun Google baru (tanpa profile lama)
  void cancelLinkGoogle() {
    _pendingLinkProfileId = null;
    _pendingLinkNickname = null;
  }

  Future<void> updateFcmToken() async {
    if (!_notificationsEnabled) return;
    // Jaringan HP sering flaky saat app baru buka (DNS/radio belum stabil) —
    // retry supaya token FCM fresh selalu tersimpan, kalau tidak push call
    // dan chat akan ditolak FCM (NotRegistered).
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final token = await FirebaseMessaging.instance.getToken();
        // JANGAN tulis token kosong! getToken() bisa mengembalikan null
        // sesaat (FCM belum siap / jaringan flaky). Dulu null → `''` ditulis
        // ke DB → token yang tadinya VALID terhapus → SEMUA push (pesan,
        // call, online) mati diam-diam untuk device itu sampai app restart
        // berhasil dapat token lagi. Ini penyebab utama "notif online mati"
        // (banyak device aktif tapi fcm_token kosong).
        if (token == null || token.isEmpty) {
          // Coba lagi sebentar — maybe FCM belum siap.
          await Future<void>.delayed(Duration(seconds: 5 * (attempt + 1)));
          continue;
        }
        await _auth.updateFcmToken(token);
        return;
      } catch (_) {
        // token tidak tersedia: coba lagi sebentar lagi
        await Future<void>.delayed(Duration(seconds: 5 * (attempt + 1)));
      }
    }
  }

  /// Muat preferensi notifikasi dari SharedPreferences (saat app start).
  Future<void> loadNotificationPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_notifPrefKey);
      if (enabled != null) {
        _notificationsEnabled = enabled;
        _emit();
      }
    } catch (_) {}
  }

  /// Toggle notifikasi ON/OFF.
  /// OFF → kosongkan fcm_token di DB agar push tidak terkirim + matikan semua toggle per-jenis.
  /// ON  → set ulang fcm_token.
  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_notifPrefKey, enabled);
      if (!enabled) {
        for (final t in NotificationPrefsService.types) {
          await prefs.setBool('notif_type_$t', false);
        }
      }
    } catch (_) {}
    if (enabled) {
      await updateFcmToken();
    } else {
      try {
        await _auth.updateFcmToken('');
      } catch (_) {}
    }
    _emit();
  }

  Future<void> retry() => _init();

  /// Simpan daftar hashtag profil (diupdate lokal + server).
  Future<void> updateHashtags(List<String> hashtags) async {
    await _auth.updateHashtags(hashtags);
    _profile = _profile?.copyWith(hashtags: hashtags);
    _emit();
  }

  /// Bersihkan presence room yang basi di server (fire-and-forget).
  Future<void> cleanupStalePresence({int minAgeMinutes = 10}) {
    return _auth.cleanupStalePresence(minAgeMinutes: minAgeMinutes);
  }

  /// Satu query ambil SEMUA setting global lalu split di memori (pengganti
  /// 7× fetch sequential saat boot — hemat 6 RPC per user). Realtime
  /// (_listenAppSettings) menutup gap perubahan setelah boot.
}
