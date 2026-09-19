part of 'auth_service.dart';

/// Domain **auth** AuthService (Fase 17) — dipisah dari file 1278 baris.
/// Satu library via `part`: field privat AuthService tetap bisa diakses,
/// interface `AuthService` tidak berubah (mock test aman).
mixin AuthServiceAuthMx on AuthBase {
  /// Cek apakah email sudah terdaftar di akun lain.
  Future<Map<String, dynamic>?> checkEmailExists(String email) async {
    try {
      final res = await _sb.rpc(
        'check_email_exists',
        params: {'p_email': email},
      );
      if (res == null) return null;
      final map = Map<String, dynamic>.from(res as Map);
      return map['exists'] == true ? map : null;
    } catch (e) {
      dlog('[AUTH] checkEmailExists error: $e');
      return null;
    }
  }

  /// Pindahkan profile dari akun lama ke akun Google baru.
  /// Ini "partial linking" — profile lama (nickname, avatar, dll) dipindah ke uid Google.
  Future<void> linkGoogleProfile(String oldProfileId) async {
    final newId = uid;
    if (newId == null) return;
    try {
      // Copy profile lama ke uid baru.
      // Exclude ip_address & fcm_token — kolom ini di-revoke dari akses
      // publik (hardening), dan tidak boleh ditimpa saat link akun.
      const cols =
          'id,nickname,gender,age,country,city,status,avatar,is_registered,hashtags,points';
      final old = await _sb
          .from('profiles')
          .select(cols)
          .eq('id', oldProfileId)
          .maybeSingle();
      if (old == null) return;

      // Upsert profile lama ke uid baru — HANYA kolom yang boleh di-SELECT
      // (kolom sensitif di-revoke dari anon/authenticated; menulisnya di
      // upsert memicu 42501). `old` sudah berisi kolom publik saja.
      await _sb.from('profiles').upsert({...old, 'id': newId});

      // Email & fcm via UPDATE terpisah (tidak butuh SELECT kolom tsb).
      final email = _sb.auth.currentUser?.email;
      await _sb.from('profiles').update({
        if (email != null && email.isNotEmpty) 'email': email,
      }).eq('id', newId);

      dlog('[AUTH] linkGoogleProfile: linked $oldProfileId -> $newId');
    } catch (e) {
      dlog('[AUTH] linkGoogleProfile error: $e');
    }
  }

  Future<void> signInAnonymously() async {
    if (_sb.auth.currentUser != null) return;
    final res = await _sb.auth.signInAnonymously();
    dlog('[AUTH] signInAnonymously -> ${res.user?.id}');
  }

  /// Login dengan email + password.
  /// Setelah ini, getProfile() akan mengembalikan profile user.
  Future<void> signInWithEmail(String email, String password) async {
    final res = await _sb.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (res.user == null) throw Exception('Login failed');
  }

  /// Upgrade anonymous account ke email account.
  /// UID tidak berubah - semua data (chat, profile) dipertahankan.
  Future<void> linkEmailToAccount(String email, String password) async {
    await _sb.auth.updateUser(UserAttributes(email: email, password: password));
  }

  /// Tandai profile sebagai terdaftar (punya email).
  /// GUARD: hanya bila sesi benar-benar punya email TERKONFIRMASI —
  /// updateUser(email) bersifat pending di GoTrue (auth.email tetap null
  /// sampai dikonfirmasi); tanpa ini akun anon bisa salah-mark registered.
  Future<void> markRegistered() async {
    final id = uid;
    if (id == null) return;
    final user = _sb.auth.currentUser;
    final email = user?.email ?? '';
    if (email.isEmpty ||
        (user!.emailConfirmedAt == null && user.phoneConfirmedAt == null)) {
      dlog('[AUTH] markRegistered skip: email belum terkonfirmasi');
      return;
    }
    try {
      await _sb
          .from('profiles')
          .update({'is_registered': true, 'email': email})
          .eq('id', id);
    } catch (e) {
      dlog('[AUTH] markRegistered error: $e');
    }
  }

  /// Cek apakah email sudah terdaftar di Auth (RPC security definer).
  /// Kalau RPC belum dibuat di DB, fallback ke [fallback]
  /// (reset: true = lanjut kirim seperti lama; signup: false = lanjut daftar).
  Future<bool> checkEmailRegistered(
    String email, {
    bool fallback = true,
  }) async {
    try {
      final res = await _sb.rpc(
        'check_email_registered',
        params: {'p_email': email},
      );
      return res == true;
    } catch (e) {
      dlog('[AUTH] checkEmailRegistered error, fallback=$fallback: $e');
      return fallback;
    }
  }

  /// Daftar akun baru dengan email + password.
  /// Mengembalikan userId — caller harus panggil registerProfile() setelahnya.
  /// Lempar [EmailAlreadyRegisteredException] jika email sudah terdaftar.
  Future<String> signUpWithEmail(String email, String password) async {
    if (await checkEmailRegistered(email, fallback: false)) {
      throw EmailAlreadyRegisteredException();
    }
    final res = await _sb.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: 'chatyuk://login-callback',
    );
    final user = res.user;
    if (user == null) throw Exception('Sign up failed: no user returned');
    // GoTrue: bila email SUDAH ada tapi belum diverifikasi, signUp ulang
    // mengembalikan user PALSU dengan `identities` kosong dan TIDAK
    // mengirim OTP baru. Deteksi & kirim ulang kode verifikasi supaya
    // pengguna tetap menerima kode (dulu: diam-diam gagal → "kode tidak
    // valid" walau belum pernah menerima kode).
    final identities = user.identities;
    if (identities != null && identities.isEmpty) {
      try {
        await resendEmailOtp(email);
      } catch (e) {
        dlog('[AUTH] signUp ulang: resend OTP error: $e');
      }
    }
    return user.id;
  }

  /// Kirim ulang email verifikasi (untuk user yang sudah signup tapi belum verify).
  Future<void> resendVerificationEmail(String email) async {
    await _sb.auth.resend(type: OtpType.signup, email: email);
  }

  /// Kirim ulang kode verifikasi (OTP) ke email — untuk user belum terverifikasi.
  Future<void> resendEmailOtp(String email) async {
    await _sb.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: 'chatyuk://login-callback',
    );
  }

  /// Verifikasi kode OTP 6 digit. Return true bila sukses.
  /// Pesan error asli GoTrue disimpan di [lastOtpError] supaya UI bisa
  /// menampilkan sebab sebenarnya (kedaluwarsa / sudah dipakai / salah) —
  /// dulu ditelan dan UI selalu bilang "kode tidak valid".
  String? lastOtpError;
  Future<bool> verifyEmailOtp(String email, String token) async {
    lastOtpError = null;
    try {
      // type harus SAMA dengan yang dipakai resend (OtpType.signup) —
      // kalau beda (mis. 'email'), server menolak kode yang valid.
      await _sb.auth.verifyOTP(
        email: email,
        token: token,
        type: OtpType.signup,
      );
      return true;
    } catch (e) {
      lastOtpError = e.toString();
      dlog('[AUTH] verifyEmailOtp error: $e');
      return false;
    }
  }

  /// Ikat diri sendiri ke referrer (sekali). Return {ok}.
  Future<bool> bindReferrer(String referrerUid) async {
    try {
      final res = await _sb.rpc(
        'bind_referrer',
        params: {'p_referrer': referrerUid},
      );
      return res is Map && res['ok'] == true;
    } catch (e) {
      dlog('[AUTH] bindReferrer error: $e');
      return false;
    }
  }

  /// Kirim email reset password.
  Future<void> sendPasswordResetEmail(String email) async {
    await _sb.auth.resetPasswordForEmail(
      email,
      redirectTo: 'chatyuk://login-callback',
    );
  }

  /// Set password baru. Dipanggil dari screen reset password
  /// setelah user membuka link recovery di email.
  Future<void> resetPassword(String newPassword) async {
    await _sb.auth.updateUser(UserAttributes(password: newPassword));
    // Logout agar user login ulang dengan password baru
    await _sb.auth.signOut();
  }

  Future<bool> fetchHasPassword() async {
    try {
      final res = await _sb.rpc('has_password');
      if (res is bool) {
        _cachedHasPassword = res;
        _hasPasswordFetched = true;
        return res;
      }
    } catch (_) {}
    final fallback = hasPassword;
    _cachedHasPassword = fallback;
    _hasPasswordFetched = true;
    return fallback;
  }

  /// Set password baru (untuk akun Google yang belum punya password).
  Future<void> setPassword(String newPassword) async {
    await _sb.auth.updateUser(UserAttributes(password: newPassword));
    _cachedHasPassword = true;
    _hasPasswordFetched = true;
  }

  /// Ganti password: verifikasi password lama dulu, lalu update.
  /// Lempar error bila password lama salah.
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    final email = userEmail;
    if (email == null || email.isEmpty) {
      throw Exception('No email on account');
    }
    await _sb.auth.signInWithPassword(email: email, password: currentPassword);
    await _sb.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Cek apakah nickname sudah dipakai oleh user lain.
  /// Nickname terlarang dianggap "tidak tersedia" untuk non-admin.
  Future<bool> isNicknameAvailable(String nickname) async {
    if (isBannedNickname(nickname) && !AdminGate.isRealAdmin(userEmail)) {
      return false;
    }
    final id = uid;
    var query = _sb.from('profiles').select('id').eq('nickname', nickname);
    if (id != null) query = query.neq('id', id);
    final res = await query.maybeSingle();
    return res == null; // null = tidak ada yang pakai
  }

  /// Ambil alih nickname milik akun anon yang tidak aktif > 7 hari
  /// (dummy yang di-uninstall tidak terhapus di server).
  Future<bool> claimNickname(String nickname) async {
    // Nickname terlarang tidak bisa diklaim (kecuali admin).
    if (isBannedNickname(nickname) && !AdminGate.isRealAdmin(userEmail)) {
      return false;
    }
    final res = await _sb.rpc(
      'claim_nickname',
      params: {'p_nickname': nickname},
    );
    return res == true;
  }

  Future<void> signOut() async {
    // Logout saat sesi dummy = KEMBALI ke admin, bukan menghancurkan sesi
    // dummy di server (signOut GoTrue akan me-revoke refresh token dummy
    // sehingga swap berikutnya gagal selamanya).
    if (_dummySessionActive) {
      final back = AdminGate.backToAdminImpl;
      if (back != null) {
        final ok = await back();
        if (ok) return;
      }
      // Kalau restore admin gagal (token admin mati), lanjut logout normal.
    }
    _dummySessionActive = false;
    _dummyUid = null;
    // Pembersihan token admin tersimpan ditangani modul admin
    // (AdminGate.onSignOut) — di build rilis hook ini tidak pernah terisi.
    try {
      await AdminGate.onSignOut?.call();
    } catch (_) {}
    try {
      // Teardown total realtime: cegah socket/channel lama nyangkut saat
      // login ulang di proses yang sama (race disconnect/connect di
      // realtime_client bisa bikin socket mati permanen).
      await _sb.realtime.removeAllChannels();
      await _sb.realtime.disconnect();
    } catch (e) {
      dlog('[AuthService] realtime teardown error: $e');
    }
    await _sb.auth.signOut();
  }
}
