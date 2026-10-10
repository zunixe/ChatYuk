part of 'auth_provider.dart';

mixin _AuthActionsMx on _AuthBase {
  Future<bool> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
  }) async {
    await _auth.signUpWithEmail(email, password);
    final user = _auth.currentUser;
    // Kalau email sudah auto-confirm → session aktif, langsung daftarkan profil.
    if (user != null && user.emailConfirmedAt != null) {
      await registerProfile(
        nickname: nickname,
        gender: gender,
        age: age,
        country: country,
        city: city,
      );
      return true;
    }
    return false;
  }

  /// Verifikasi kode OTP email, lalu daftarkan profil. Return true bila sukses.
  Future<bool> verifyEmailAndRegister({
    required String email,
    required String token,
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
  }) async {
    final ok = await _auth.verifyEmailOtp(email, token);
    // Simpan pesan error asli (kedaluwarsa/dipakai/salah) untuk UI.
    lastOtpError = _auth.lastOtpError;
    if (!ok) return false;
    await registerProfile(
      nickname: nickname,
      gender: gender,
      age: age,
      country: country,
      city: city,
    );
    return true;
  }

  /// Pesan error asli verifikasi OTP terakhir (null bila sukses).
  String? lastOtpError;

  /// Email user aktif sudah terverifikasi?
  bool get emailConfirmed => _auth.emailConfirmed;

  /// Boleh pakai fitur point berbayar? (harus registered + email verified)
  bool get canUsePaid =>
      (profile?.isRegistered ?? false) && _auth.emailConfirmed;

  /// Kirim ulang kode verifikasi OTP.
  Future<void> resendEmailOtp(String email) => _auth.resendEmailOtp(email);

  /// Set password untuk akun Google yang belum punya password.
  Future<void> setPassword(String newPassword) =>
      _auth.setPassword(newPassword);

  /// Ganti password (akun email). Verifikasi password lama dulu.
  Future<void> changePassword(String currentPassword, String newPassword) =>
      _auth.changePassword(currentPassword, newPassword);

  /// Login dengan email + password.
  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmail(email, password);
    _profile = await _auth.getProfile();
    _listenProfile();
    _restartPresenceTimers();
    if (_profile != null) await updateFcmToken();
    _syncTikTok(event: TikTokEvent.LOGIN);
    _emit();
  }

  /// Upgrade anonymous account ke email account. UID tetap sama.
  Future<void> linkEmailToAccount(String email, String password) async {
    await _auth.linkEmailToAccount(email, password);
    await _auth.markRegistered();
    _profile = _profile?.copyWith(isRegistered: true);
    // Welcome bonus: klaim 'anon' (bila belum — user daftar langsung dapat
    // full) lalu 'register'. Server idempoten per install_id.
    safeUnawaited(_claimWelcomeFull());
    safeUnawaited(updateFcmToken());
    _emit();
  }

  /// Klaim welcome anon + register berurutan (untuk register langsung).
  Future<void> _claimWelcomeFull() async {
    await _claimWelcome('anon');
    await _claimRegisterBonus();
  }

  /// Daily-login bonus DIHAPUS (overhaul coin: tidak ada poin gratis). No-op.
  Future<void> _claimDailyPoints() async {
    // Faucet dihapus — tidak ada bonus login. (lihat 20261001010000)
  }

  /// Welcome bonus REGISTER (100 coin) via server sekali per install_id.
  Future<void> _claimRegisterBonus() async {
    await _claimWelcome('register');
  }

  /// Klaim welcome bonus (anon/register). Kirim install_id device (stabil
  /// walau reinstall) — server cegah klaim ulang per device & limit IP.
  Future<int> _claimWelcome(String kind) async {
    try {
      final installId = await DeviceInfoService.instance.installId();
      if (installId.isEmpty) return 0;
      final res = await PointsService().claimWelcomeBonus(
        installId: installId,
        kind: kind,
      );
      final coins = (res['coins'] as num?)?.toInt() ?? 0;
      if (coins > 0) {
        final cur = (_profile?.points ?? 0).toInt();
        _profile = _profile?.copyWith(points: cur + coins);
        _emit();
      }
      return coins;
    } catch (e) {
      dlog('[AUTH] claimWelcome($kind) error: $e');
      return 0;
    }
  }

  /// Kirim ulang email verifikasi untuk user yang sudah signup tapi belum verify.
  Future<void> resendVerificationEmail(String email) async {
    await _auth.resendVerificationEmail(email);
  }

  /// Kirim email reset password.
  /// Lempar [EmailNotRegisteredException] jika email belum terdaftar.
  Future<void> sendPasswordResetEmail(String email) async {
    final registered = await _auth.checkEmailRegistered(email);
    if (!registered) throw EmailNotRegisteredException();
    await _auth.sendPasswordResetEmail(email);
  }

  /// Set password baru setelah recovery. Logout otomatis agar login ulang.
  Future<void> resetPassword(String newPassword) async {
    _idleTimer?.cancel();
    _heartbeatTimer?.cancel();
    _locationTimer?.cancel();
    _isIdle = false;
    _manualSignOut = true;
    // Sama seperti signOut(): tandai transisi keluar supaya gate root
    // langsung EntryScreen, bukan `_ProfileGate`/MainNav sekejap.
    _signingOut = true;
    _loading = true;
    _emit();
    try {
      await _auth.resetPassword(newPassword);
    } finally {
      _manualSignOut = false;
    }
    _profile = null;
    _loading = false;
    _signingOut = false;
    _emit();
  }

  /// Cek apakah nickname tersedia.
  Future<bool> isNicknameAvailable(String nickname) {
    return _auth.isNicknameAvailable(nickname);
  }

  Future<bool> claimNickname(String nickname) {
    return _auth.claimNickname(nickname);
  }

  Future<void> registerProfile({
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
    String ipAddress = '',
  }) async {
    dlog('[AUTH] registerProfile START: $nickname inst=$instanceId');
    try {
      _profile = await _auth.registerProfile(
        nickname: nickname,
        gender: gender,
        age: age,
        country: country,
        city: city,
        ipAddress: ipAddress,
      );
    } catch (e) {
      // User anon lama bisa dihapus di server oleh cleanup_stale_anonymous
      // (akun stale > 7 hari). Session masih ada di device tapi user tidak
      // lagi ada di auth.users → insert profile gagal FOREIGN KEY.
      // Deteksi & buat user anon baru, lalu retry sekali.
      //
      // PENTING: HANYA 23503/FK yang menandakan "stale anon". JANGAN
      // menganggap 42501 (permission denied) sebagai stale — dulu di sini,
      // error izin (mis. grant SELECT dicabut dari ON CONFLICT) ikut
      // tertangkap sebagai "stale" → app sign out + bikin user anon BARU
      // padahal session valid → nickname user hilang / dianggap "sudah
      // digunakan". (Insiden 2026-10-04.)
      final msg = e.toString().toLowerCase();
      final userInvalid =
          msg.contains('23503') ||
          msg.contains('foreign key') ||
          msg.contains('profiles_id_fkey');
      if (userInvalid) {
        dlog(
          '[AUTH] registerProfile failed (stale anon), refreshing session: $e',
        );
        _manualSignOut = true;
        try {
          await _auth.signOut();
        } finally {
          _manualSignOut = false;
        }
        await _auth.signInAnonymously();
        _profile = await _auth.registerProfile(
          nickname: nickname,
          gender: gender,
          age: age,
          country: country,
          city: city,
          ipAddress: ipAddress,
        );
      } else {
        rethrow;
      }
    }
    dlog(
      '[AUTH] registerProfile DONE: ${_profile?.uid} inst=$instanceId hasListeners=mounted',
    );
    _emit();
    dlog(
      '[AUTH] emit, profile=${_profile?.uid} inst=$instanceId hasListeners=mounted',
    );
    resetIdleTimer();
    _restartPresenceTimers();
    // Fire-and-forget: di HP tanpa GMS (mis. Huawei) getToken() melempar —
    // jangan biarkan unhandled async error mengganggu alur registrasi.
    safeUnawaited(updateFcmToken());
    // Ikat referrer (bila ada) — sekali saja, setelah profil terdaftar.
    _bindAndClaimReferrer();
    // TikTok Ads: identify + event REGISTRATION (user menyelesaikan daftar).
    _syncTikTok(event: TikTokEvent.REGISTRATION);
  }

  // ── Passthrough agar screen tidak import AuthService (Fase 9b) ──
  Future<List<UserPhoto>> getPhotos(String uid) => _auth.getPhotos(uid);
  Future<List<UserPhoto>> getPhotosWithAccess(String uid) =>
      _auth.getPhotosWithAccess(uid);
  Future<void> uploadPhoto(String base64, {String? preview}) =>
      _auth.uploadPhoto(base64, preview: preview);
  Future<void> deletePhoto(String photoId) => _auth.deletePhoto(photoId);
  Future<void> deleteMyAccount() => _auth.deleteMyAccount();

  Future<void> updateProfile({
    int? age,
    String? country,
    String? city,
    String? nickname,
    String? about,
    String? gender,
    DateTime? birthDate,
    String? phone,
  }) async {
    await _auth.updateProfile(
      age: age,
      country: country,
      city: city,
      nickname: nickname,
      about: about,
      gender: gender,
      birthDate: birthDate,
      phone: phone,
    );
    final aboutText = about?.trim();
    final savedAbout = aboutText == null
        ? null
        : (aboutText.length > 150 ? aboutText.substring(0, 150) : aboutText);
    _profile = _profile?.copyWith(
      age: age ?? _profile?.age,
      country: country ?? _profile?.country,
      city: city ?? _profile?.city,
      nickname: nickname ?? _profile?.nickname,
      about: savedAbout,
      gender: gender ?? _profile?.gender,
      birthDate: birthDate ?? _profile?.birthDate,
      phone: phone != null ? normalizePhone(phone) : _profile?.phone,
    );
    _emit();
  }

  /// Update IP address di server (tidak disimpan di aplikasi).
  Future<void> updateIpAddress(String ip) => _auth.updateIpAddress(ip);

  Future<void> updateAvatar(String base64) async {
    final serverPath = await _auth.updateAvatar(base64);
    final uid = _profile?.uid ?? _auth.uid ?? '';
    if (uid.isNotEmpty) {
      AvatarB64Service.instance.setForUid(uid, base64);
      ChatService.setAvatarCacheForUid(uid, base64);
      // Path baru tercatat — realtime/meta & disk sinkron mengikuti.
      if (serverPath.isNotEmpty) {
        AvatarB64Service.instance.setForPath(serverPath, base64);
      }
    }
    _profile = _profile?.copyWith(avatar: base64);
    _emit();
  }

  Future<void> removeAvatar() async {
    await _auth.removeAvatar();
    final uid = _profile?.uid ?? _auth.uid ?? '';
    if (uid.isNotEmpty) {
      AvatarB64Service.instance.clearForUid(uid);
      ChatService.clearAvatarCacheForUid(uid);
    }
    _profile = _profile?.copyWith(avatar: '');
    _emit();
  }

  Future<void> signOut() async {
    _manualSignOut = true;
    // Tandai "sedang keluar" SEBELUM sesi dihapus: gate root memakai ini
    // untuk langsung pindah ke EntryScreen. Tanpa flag ini, `_profile=null`
    // sementara `dummySessionActive` sudah false membuat `needsProfile`
    // bernilai true → `_ProfileGate(child: _MainNav())` ter-render sekejap
    // (flash halaman utama + popup isi profil) sebelum EntryScreen.
    _signingOut = true;
    _loading = true;
    _emit();
    // TikTok Ads: reset identitas sebelum sesi dihapus (panduan TikTok —
    // logout dulu, identify ulang saat login berikutnya).
    safeUnawaited(TikTokService.instance.logout());
    try {
      _idleTimer?.cancel();
      _heartbeatTimer?.cancel();
      _locationTimer?.cancel();
      _profileSub?.cancel();
      _isIdle = false;
      await _auth.goOffline();
      // Sesi lokal WAJIB dibuang apa pun hasil revoke server: network
      // error/timeout di sini dulu melempar keluar sehingga `_loading`
      // tetap true selamanya → gate root nyangkut di splash dan user
      // tidak pernah kembali ke halaman utama.
      try {
        await _auth.signOut().timeout(const Duration(seconds: 8));
      } catch (e) {
        dlog('[AUTH] signOut error (lanjut paksa keluar): $e');
      }
      _profile = null;
      // Hapus cache profil supaya login berikutnya tidak tampil data lama.
      try {
        final prefs = await SharedPreferences.getInstance();
        final keys = prefs
            .getKeys()
            .where((k) => k.startsWith(_profileCachePrefix))
            .toList();
        for (final k in keys) {
          await prefs.remove(k);
        }
      } catch (_) {}
      // Buang SEMUA cache gambar (bitmap + bytes foto chat) — HP bisa
      // dipakai bergantian orang; foto user lama tidak boleh tinggal di RAM.
      ImageCacheHygiene.clearAll();
      // Sesi benar-benar kosong sekarang → EntryScreen (bukan splash).
      // `loading=false` + `profile=null` + `signingOut=true` = gate root
      // menampilkan EntryScreen pada frame yang sama.
      _loading = false;
      _emit();
    } finally {
      _manualSignOut = false;
      _signingOut = false;
      // Jaring pengaman: gate root HARUS rebuild apa pun yang terjadi di
      // atas (termasuk timeout 8s yang dibatalkan pemanggil) — tanpa ini
      // gate bisa tertinggal di splash bila notify terakhir terlewat.
      _loading = false;
      _emit();
    }
  }

  /// True saat sesi aktif adalah akun dummy (bukan admin).
  bool get dummySessionActive => _auth.dummySessionActive;

  /// Pindah ke akun dummy (swap sesi tanpa login manual). Profile di-reload
  /// supaya seluruh UI (lobby, profil) langsung memakai akun dummy.
  Future<void> becomeDummy(String uid) async {
    final impl = AdminGate.becomeDummyImpl;
    if (impl == null) {
      throw StateError('becomeDummy hanya tersedia di build admin');
    }
    await impl(uid);
    // Belt-and-suspenders: pastikan flag sesi dummy ter-set di service yang
    // dipakai provider ini (impl juga set, tapi jangan bergantung binding).
    _auth.markDummyState(active: true, uid: uid);
    dlog(
      '[AUTH] becomeDummy done, uid=$_auth.uid, '
      'flag=${_auth.dummySessionActive}',
    );
    await reloadProfile();
    // Catat device untuk akun dummy — tanpa ini dummy tidak muncul di tab
    // Perangkat admin (dummy dibuat via edge function, tidak pernah lewat
    // alur login yang memanggil syncToServer). Tercatat pakai HP admin
    // (install_id perangkat aktif saat swap).
    safeUnawaited(DeviceInfoService.instance.syncToServer());
  }

  /// Kembali ke akun admin dari sesi dummy. Return false jika token admin
  /// kedaluwarsa (perlu login manual).
  Future<bool> backToAdmin() async {
    final impl = AdminGate.backToAdminImpl;
    if (impl == null) return false;
    final ok = await impl();
    // Flag dummy dibersihkan APA PUN hasilnya: sukses = sesi admin; gagal =
    // sesi mati total — keduanya bukan sesi dummy, banner tidak boleh
    // nempel (dulu: gagal → flag tetap true → banner tampil di akun admin
    // setelah login manual = "setengah admin setengah engga").
    _auth.markDummyState(active: false);
    await reloadProfile();
    return ok;
  }

  /// Reload profile untuk user sesi aktif sekarang (dipakai setelah swap
  /// sesi dummy ⇄ admin, karena event signedIn tidak di-trigger manual).
  Future<void> reloadProfile() async {
    _profileSub?.cancel();
    // Tahap cepat: identitas dasar TANPA download avatar → UI langsung
    // pindah ke profil user baru saat swap sesi dummy ⇄ admin.
    try {
      final lite = await _auth.getProfile(withAvatar: false);
      dlog('[AUTH] reloadProfile lite -> ${lite?.uid} ${lite?.nickname}');
      if (lite != null && !_disposed) {
        _profile = lite;
        safeUnawaited(_saveCachedProfile(lite));
        _emit();
      }
    } catch (e) {
      // Jaringan flaky — jangan biarkan exception menggagalkan swap.
      dlog('[AUTH] reloadProfile lite FAILED: $e');
    }
    // Tahap lengkap: avatar (cache per path, biasanya instan).
    try {
      _profile = await _auth.getProfile();
      // DIAG2 sementara.
      print('[ABOUT2] reloadProfile full about="${_profile?.about}"');
      dlog('[AUTH] reloadProfile full -> ${_profile?.uid}');
    } catch (e) {
      dlog('[AUTH] reloadProfile full FAILED: $e');
    }
    // Akun banned: paksa offline supaya hilang dari daftar online.
    if (isProfileBanned) safeUnawaited(_auth.goOffline());
    _listenProfile();
    _restartPresenceTimers();
    // Update FCM token untuk sesi yang baru aktif (swap dummy ⇄ admin) —
    // tanpa ini, token FCM profil dummy tidak ter-update ke device fisik
    // ini sehingga push call/chat ke dummy ditolak (NotRegistered).
    if (_profile != null) safeUnawaited(updateFcmToken());
    _emit();
  }

  /// Waktu interaksi terakhir — dipakai throttle [notifyActivity] supaya
  /// tiap pointer-down tidak membuat object Timer baru (perf: Listener
  /// global di app.dart memanggil ini pada SETIAP sentuhan).
  DateTime? _lastActivityAt;

  /// Call on any user interaction (tap, scroll, typing...).
  /// If user was idle, go back online. Resets the idle countdown.
  void notifyActivity() {
    if (_idleTimer == null) return; // not signed in yet
    if (isProfileBanned) return; // banned → tetap offline, jangan online lagi
    if (dummySessionActive) return; // status dummy dikontrol admin panel
    if (_invisibleEnabled) return; // invisible → jangan pernah kembali online
    // Throttle: idle→online tetap selalu diproses (penting), tapi reset
    // timer dibatasi 1× per detik — idleTimeout jauh lebih besar dari itu
    // sehingga presisinya tidak berubah.
    final now = DateTime.now();
    final last = _lastActivityAt;
    final throttled =
        last != null && now.difference(last) < const Duration(seconds: 1);
    if (_isIdle) {
      _isIdle = false;
      _lastActivityAt = now;
      _auth.goOnline();
      _profile = _profile?.copyWith(status: 'online');
      // TIDAK memanggil _updateLocationOnOnline() di sini.
      // AKAR (terukur): notifyActivity dipanggil pada SETIAP pointer-down
      // (listener global app.dart). User yang menyentuh layar setelah idle
      // → GPS menyala → `GeolocatorLocationService` ter-BIND ke proses →
      // MIUI menganggap app aktif terus (proses tak pernah di-freeze,
      // oom_score_adj=0) → panel tidak masuk mode hemat → frame pertama
      // setelah resume menunggu panel bangun ~180ms (framestats ui_work=0ms,
      // Vsync melompat +181ms). App yang MULUS di HP ini (Shopee/WhatsApp)
      // justru CACHED (oom 701).
      // Lokasi diperbarui lewat ping 5 menit (_startLocationPing) & saat
      // login — tidak perlu tiap sentuhan.
      _emit();
    } else {
      if (throttled) return;
      _lastActivityAt = now;
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, _becomeIdle);
  }

  void resetIdleTimer() {
    if (dummySessionActive) return; // status dummy dikontrol admin panel
    _isIdle = false;
    _idleTimer?.cancel();
    if (_invisibleEnabled) return;
    _idleTimer = Timer(idleTimeout, _becomeIdle);
  }

  Future<void> _becomeIdle() async {
    if (_disposed) return;
    if (isProfileBanned) {
      await _auth.goOffline();
      _profile = _profile?.copyWith(status: 'offline');
      _emit();
      return;
    }
    if (dummySessionActive) return; // status dummy dikontrol admin panel
    if (_invisibleEnabled) return;
    _isIdle = true;
    await _auth.goIdle();
    _profile = _profile?.copyWith(status: 'idle');
    _emit();
  }

  Future<void> goOnline() async {
    if (_disposed) return;
    if (isProfileBanned) return; // banned → tetap offline
    if (dummySessionActive) return;
    if (_invisibleEnabled) return;
    await _auth.goOnline();
    _profile = _profile?.copyWith(status: 'online');
    _emit();
    resetIdleTimer();
    // CATATAN (terukur): JANGAN nyalakan GPS di sini (dulu memanggil
    // _startLocationPing + _updateLocationOnOnline). Keduanya membuat
    // GeolocatorLocationService tetap BOUND ke proses → MIUI menganggap app
    // "aktif terus" (proses tak pernah di-freeze, oom_score_adj=0) → panel
    // tidak pernah masuk mode hemat → frame pertama setelah resume menunggu
    // panel bangun ~180ms (framestats ui_work=0ms, Vsync melompat +181ms).
    // Semua app yang terasa MULUS di HP ini (Shopee/WhatsApp) justru CACHED
    // (oom_score_adj=701).
    //
    // Lokasi sudah dicatat saat login (via _init) dan saat Nearby dibuka
    // (layar itu memanggil updateMyLocation sendiri). Lihat goIdle() yang
    // mematikan ping saat app di-background.
    // Catat ulang Device ID tiap online/resume — self-healing: kalau sync
    // saat login gagal sesaat (jaringan), device tetap terdeteksi di admin
    // pada kesempatan berikutnya. Tanpa ini banyak device tak tercatat.
    if (_profile != null) {
      safeUnawaited(DeviceInfoService.instance.syncToServer());
    }
    if (uid != null) {
      safeUnawaited(
        RealtimeHub.instance.trackOnline(uid!, _profile?.nickname ?? ''),
      );
    }
  }

  /// Set status idle — dipakai saat app di-background/tutup (bukan logout).
  Future<void> goIdle() async {
    if (_disposed) return;
    if (dummySessionActive) return;
    if (_invisibleEnabled) return;
    _idleTimer?.cancel();
    // HENTIKAN ping lokasi saat app di-background (dipanggil dari lifecycle
    // paused). AKAR "admin ngelag saat buka chat setelah background":
    //   GeolocatorLocationService (foreground service) tetap HIDUP karena
    //   timer ping lokasi 5 menit → proses TIDAK pernah di-freeze MIUI
    //   (oom_score_adj=0, sedangkan app yang mulus seperti Shopee = 701
    //   cached). Karena proses selalu "aktif", MIUI membiarkan panel masuk
    //   DDIC idle → frame pertama setelah resume menunggu panel bangun
    //   ~165ms (framestats: ui_work=0ms, Vsync melompat).
    // Saat kembali online (goOnline/resume) ping dinyalakan lagi — lihat
    // _startLocationPing dipanggil di goOnline.
    _locationTimer?.cancel();
    _locationTimer = null;
    _isIdle = true;
    await _auth.goIdle();
    _profile = _profile?.copyWith(status: 'idle');
    _emit();
    safeUnawaited(RealtimeHub.instance.untrackOnline());
  }

  Future<void> goOffline() async {
    _idleTimer?.cancel();
    _isIdle = false;
    await _auth.goOffline();
    _profile = _profile?.copyWith(status: 'offline');
    _emit();
    safeUnawaited(RealtimeHub.instance.untrackOnline());
  }

  /// Heartbeat berkala: update last_seen di server tiap 240 detik + Presence.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (_disposed) return;
      if (isProfileBanned) return; // banned → jangan refresh last_seen
      safeUnawaited(_auth.updateLastSeen());
      // Hemat presence: re-track HANYA bila channel putus (dulu tiap 120 dtk
      // untrack+subscribe ulang → flap presence massal).
      if (uid != null &&
          !_invisibleEnabled &&
          !_isIdle &&
          !RealtimeHub.instance.isOnlineTracking) {
        safeUnawaited(
          RealtimeHub.instance.trackOnline(uid!, _profile?.nickname ?? ''),
        );
      }
    });
  }

  /// True bila sesi ini sedang ONLINE (bukan idle/invisible/dummy/banned).
  /// Dipakai gate pencatatan lokasi: GPS & IP hanya dicatat saat online —
  /// supaya yang tersimpan adalah lokasi terakhir saat benar-benar aktif,
  /// bukan posisi acak saat app idle di belakang.
  bool get _isLocationEligible {
    if (_disposed || dummySessionActive) return false;
    if (isProfileBanned) return false;
    if (_invisibleEnabled) return false;
    if (_isIdle) return false;
    return true;
  }

  /// Update lokasi berkala (5 menit) HANYA saat online — pin di peta admin
  /// dan daftar orang sekitar selalu segar. GPS dipakai kalau izin sudah
  /// ada, else perkiraan IP. Gagal diam-diam (tidak mengganggu apapun).
  ///
  /// PERF (terukur): dipanggil HANYA setelah lokasi pertama selesai
  /// disimpan (location_init_done). Sebelum ini, `updateMyLocation()`
  /// memanggil `Geolocator.getCurrentPosition` walau GPS tak diperlukan —
  /// itu membuat `GeolocatorLocationService` ter-BIND ke proses terus,
  /// sehingga MIUI menganggap app "aktif selalu" (proses tak di-freeze,
  /// oom_score_adj=0) → frame pertama setelah resume tertahan ~180ms
  /// menunggu panel bangun. App yang MULUS di HP ini (Shopee/WhatsApp)
  /// justru CACHED (oom 701).
  void _startLocationPing() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (!_isLocationEligible) return;
      // Lewati bila lokasi belum pernah tersimpan sukses (mis. user belum
      // beri izin) — jangan paksa GPS hidup tiap 5 menit untuk no-op.
      safeUnawaited(LocationService().updateMyLocation());
    });
  }

  /// Update + catat history posisi saat status berubah jadi online
  /// (idle→online, invisible→online, panggil goOnline). Fire-and-forget,
  /// GPS dipakai kalau izin ada, else perkiraan IP.
  Future<void> _updateLocationOnOnline() async {
    if (_disposed || dummySessionActive) return;
    if (isProfileBanned) return;
    try {
      await LocationService().updateMyLocation();
    } catch (e) {
      dlog('[AUTH] location on online error: $e');
    }
  }

  /// Arm ulang timer presence (heartbeat + lokasi) setelah (re)login.
  /// signOut / signedOut men-cancel keduanya, dan _init hanya jalan sekali
  /// saat konstruksi — tanpa ini, user aktif tetap tampil offline setelah
  /// ganti akun (last_seen basi > 30 menit).
  void _restartPresenceTimers() {
    if (_disposed) return;
    _startHeartbeat();
    _startLocationPing();
    safeUnawaited(_initLocation());
  }

  /// Minta izin lokasi saat app start (dialog native) lalu update lokasi.
  /// Dijalankan di semua jalur login — termasuk session anonymous yang
  /// auto-restore (di situ LoginScreen tidak pernah tampil). Kalau izin
  /// sudah pernah ditentukan (mis. cuma "kira-kira"), Android tidak
  /// menampilkan dialog lagi → arahkan user ke Pengaturan sekali saja.
  Future<void> _initLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // SEKALI per install: jangan panggil GPS lagi kalau sudah pernah sukses.
      //
      // AKAR (terukur): _initLocation dipanggil tiap app dibuka (cold start &
      // resume) dan SELALU memanggil requestPermission + updateMyLocation →
      // `GeolocatorLocationService` ter-BIND ke proses → MIUI menganggap app
      // "aktif terus" (proses tak pernah di-freeze, oom_score_adj=0) → panel
      // tidak masuk mode hemat → frame pertama setelah resume menunggu panel
      // bangun ~180ms (framestats: ui_work=0ms, Vsync melompat +181ms).
      // App yang MULUS di HP ini (Shopee/WhatsApp) justru CACHED (oom 701).
      //
      // Lokasi tetap segar lewat: ping 5 menit saat online (_startLocationPing)
      // dan panggilan di layar yang memang butuh (Nearby / kirim lokasi).
      if (prefs.getBool('location_init_done') ?? false) return;
      final loc = LocationService();
      await loc.requestPermission();
      // Kalau lokasi TIDAK tersimpan sama sekali (GPS & IP gagal) →
      // besar kemungkinan izin presisi (FINE) belum diberikan dan
      // Android tidak mau menampilkan dialog lagi → arahkan ke Settings.
      final source = await loc.updateMyLocation();
      if (source != null) {
        await prefs.setBool('location_init_done', true);
        return;
      }
      final prompted = prefs.getBool('location_settings_prompted') ?? false;
      if (!prompted && !_disposed) {
        await prefs.setBool('location_settings_prompted', true);
        _promptLocationSettings();
      }
    } catch (e) {
      dlog('[AUTH] _initLocation error: $e');
    }
  }

  /// Dialog sekali: arahkan ke Pengaturan kalau lokasi presisi mati.
  void _promptLocationSettings() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final s = ProviderScope.containerOf(
      ctx,
      listen: false,
    ).read(localeProvider).s;
    showDialog(
      context: ctx,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(
          s.locPrecisionTitle,
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          s.locPrecisionOff,
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dctx);
              await LocationService().openSettings();
              // Setelah balik dari Settings, coba simpan lokasi lagi.
              await LocationService().updateMyLocation();
            },
            child: Text(s.locOpenSettings),
          ),
        ],
      ),
    );
  }

  void _listenProfile() {
    _profileSub?.cancel();
    _profileSub = _auth.onMyProfileUpdates().listen(
      (rec) {
        if (_disposed) return;
        _applyProfileUpdate(rec.model, presentKeys: rec.keys);
      },
      onError: (e) {
        dlog('[AUTH] profile stream error: $e');
      },
    );
  }

  /// Gabung event profil dengan state lokal: hanya kolom yang ADA di
  /// payload event yang diambil; sisanya dipertahankan dari state saat ini.
  ///
  /// Latar: payload realtime tidak memuat kolom yang di-revoke dari role
  /// authenticated (about/status/avatar/last_seen/dll). Replace mentah
  /// menimpa kolom-kolom itu dengan default kosong (gejala: Tentang tampil
  /// lalu hilang lagi). Murni supaya bisa di-unit-test.
  /// Terapkan update profil lintas-device: kalau avatar berupa path storage
  /// (re-upload dari device lain), download dulu → sinkronkan cache → baru
  /// tampilkan. Tanpa ini device kedua menampilkan foto LAMA dari cache.
  Future<void> _applyProfileUpdate(
    UserModel updated, {
    Set<String>? presentKeys,
  }) async {
    if (_disposed) return;
    // Merge kolom yang hadir saja (lihat mergeProfileEvent): payload
    // realtime tidak memuat kolom revoked → jangan timpa dengan default.
    // presentKeys null = model penuh (mis. refreshProfile) → pakai mentah.
    final merged = presentKeys == null
        ? updated
        : mergeProfileEvent(
            current: _profile,
            event: updated,
            presentKeys: presentKeys,
          );
    final avatar = merged.avatar;
    if (avatar.isNotEmpty &&
        StoragePhotoService.instance.isAvatarPath(avatar)) {
      final b64 = await AvatarB64Service.instance.getByPath(avatar);
      if (_disposed) return;
      // ANTI-HILANG: download gagal (jaringan/storage sesaat) TIDAK boleh
      // mengosongkan foto yang sudah tampil. Dulu `copyWith(avatar: b64)`
      // dengan b64='' → foto profil hilang sampai event realtime berikutnya
      // (gejala "kadang ada kadang hilang" di halaman Profil).
      final prev = _profile?.avatar ?? '';
      final keep = b64.isNotEmpty ? b64 : prev;
      if (b64.isEmpty && prev.isNotEmpty) {
        dlog('[AUTH] avatar gagal diunduh, pertahankan foto lama (${avatar})');
      }
      final finalProfile = merged.copyWith(avatar: keep);
      final uid = finalProfile.uid;
      if (b64.isNotEmpty) {
        AvatarB64Service.instance.setForUid(uid, b64);
        ChatService.setAvatarCacheForUid(uid, b64);
      }
      _profile = finalProfile;
    } else {
      // Avatar kosong di payload (mis. field belum ikut terkirim): jangan
      // buang foto lama — hanya ganti kalau payload memang membawa nilai.
      var next = merged;
      final prev = _profile?.avatar ?? '';
      if (avatar.isEmpty && prev.isNotEmpty) {
        next = merged.copyWith(avatar: prev);
      }
      _profile = next;
      if (avatar.isNotEmpty) {
        AvatarB64Service.instance.setForUid(merged.uid, avatar);
        ChatService.setAvatarCacheForUid(merged.uid, avatar);
      }
    }
    _emit();
  }

  /// Refresh profil dari server (download avatar bila path baru) — dipanggil
  /// saat app RESUME dari sleep lama, karena event realtime bisa terlewat
  /// selama proses dibekukan.
  Future<void> refreshProfile() async {
    try {
      final full = await _auth.getProfile(withAvatar: true);
      if (full == null || _disposed) return;
      await _applyProfileUpdate(full);
    } catch (e) {
      dlog('[AUTH] refreshProfile error: $e');
    }
  }

  void _disposeAll() {
    _disposed = true;
    _idleTimer?.cancel();
    _heartbeatTimer?.cancel();
    _locationTimer?.cancel();
    _profileSub?.cancel();
    _authStateSub?.cancel();
    _appSettingsSub?.cancel();
    _settingsPollTimer?.cancel();
  }
}
