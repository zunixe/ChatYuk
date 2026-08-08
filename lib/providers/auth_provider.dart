import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/screen_secure_service.dart';

// Shortcut untuk fire-and-forget
void unawaited(Future<void> future) => future.catchError((_) {});

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
  final String instanceId = 'AP-${DateTime.now().microsecondsSinceEpoch.toString().substring(8)}';
  UserModel? _profile;
  bool _loading = true;
  bool _disposed = false;
  bool _initInProgress = false;

  String? _error;

  Timer? _idleTimer;
  bool _isIdle = false;
  static const Duration idleTimeout = Duration(minutes: 3);

  static const String _notifPrefKey = 'notif_enabled';
  bool _notificationsEnabled = true;

  bool _screenshotEnabled = true;

  UserModel? get profile => _profile;
  bool get loading => _loading;
  String? get error => _error;
  bool get screenshotEnabled => _screenshotEnabled;
  bool get isSignedIn => _auth.isSignedIn;
  String? get uid => _auth.uid;
  bool get isAnonymous => _auth.isAnonymous;
  String? get userEmail => _auth.userEmail;
  bool get notificationsEnabled => _notificationsEnabled;

  AuthProvider() {
    debugPrint('[AUTH-PROVIDER] CONSTRUCTED $instanceId');
    _init();
    loadNotificationPref();
  }

  Future<void> _init() async {
    if (_initInProgress) return; // guard re-entry
    _initInProgress = true;
    debugPrint('[AUTH] _init start');
    _loading = true;
    _error = null;
    if (!_disposed) notifyListeners();
    try {
      debugPrint('[AUTH] signInAnonymously...');
      await _auth.signInAnonymously();
      debugPrint('[AUTH] signInAnonymously OK');
      _profile = await _auth.getProfile();
      debugPrint('[AUTH] getProfile -> ${_profile?.uid}');
      // Terapkan setting admin: izinkan screenshot aplikasi atau tidak
      await _loadScreenshotSetting();
      // FCM token di-fetch asinkron — jangan block loading screen
      if (_profile != null) updateFcmToken();
      // Bersihkan akun anonymous stale (fire-and-forget) supaya nickname
      // bebas dan tidak ada ghost "online". Tidak block startup.
      cleanupStaleAnonymous();
    } catch (e) {
      debugPrint('[AUTH] _init ERROR: $e');
      _error = e.toString();
    }
    _loading = false;
    _initInProgress = false;
    if (!_disposed) notifyListeners();
    debugPrint('[AUTH] _init done loading=false');
  }

  /// Login anonim (fallback saat session hilang).
  /// Setelah login, ambil profile jika sudah ada.
  Future<void> signInAnonymously() async {
    await _auth.signInAnonymously();
    _profile = await _auth.getProfile();
    if (!_disposed) notifyListeners();
  }

  /// Login dengan Google SSO via Supabase.
  /// Return:
  ///   'linked'  — email sudah ada di akun lain, profile berhasil di-link
  ///   'linked_existing' — email sudah ada, tapi user menolak linking (tetap pakai akun baru)
  ///   'new'     — user baru, perlu isi profile
  ///   'exists'  — profile sudah ada (login ulang)
  Future<String> signInWithGoogle() async {
    final result = await _auth.signInWithGoogle();
    final googleEmail = result.googleEmail;
    print('[AUTH-PROVIDER] signInWithGoogle result uid=${result.response.user?.id} email=$googleEmail');

    // Cek apakah email ini sudah punya profile di akun lain
    if (googleEmail != null) {
      final existing = await _auth.checkEmailExists(googleEmail);
      print('[AUTH-PROVIDER] checkEmailExists result=$existing');
      if (existing != null) {
        _pendingLinkProfileId = existing['profile_id'] as String?;
        _pendingLinkNickname = existing['nickname'] as String?;
        _profile = await _auth.getProfile();
        if (!_disposed) notifyListeners();
        return 'link_prompt';
      }
    }

    _profile = await _auth.getProfile();
    print('[AUTH-PROVIDER] getProfile after google -> ${_profile?.uid}');
    if (!_disposed) notifyListeners();
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
    _pendingLinkProfileId = null;
    _pendingLinkNickname = null;
    if (!_disposed) notifyListeners();
  }

  /// Tolak linking — tetap pakai akun Google baru (tanpa profile lama)
  void cancelLinkGoogle() {
    _pendingLinkProfileId = null;
    _pendingLinkNickname = null;
  }

  Future<void> updateFcmToken() async {
    if (!_notificationsEnabled) return;    try {
      final token = await FirebaseMessaging.instance.getToken();
      await _auth.updateFcmToken(token);
    } catch (_) {
      // token tidak tersedia: abaikan
    }
  }

  /// Muat preferensi notifikasi dari SharedPreferences (saat app start).
  Future<void> loadNotificationPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_notifPrefKey);
      if (enabled != null) {
        _notificationsEnabled = enabled;
        if (!_disposed) notifyListeners();
      }
    } catch (_) {}
  }

  /// Toggle notifikasi ON/OFF.
  /// OFF → kosongkan fcm_token di DB agar push tidak terkirim.
  /// ON  → set ulang fcm_token.
  Future<void> setNotificationsEnabled(bool enabled) async {
    _notificationsEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_notifPrefKey, enabled);
    } catch (_) {}
    if (enabled) {
      await updateFcmToken();
    } else {
      try { await _auth.updateFcmToken(''); } catch (_) {}
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> retry() => _init();

  /// Ambil setting admin global (screenshot enabled?) lalu terapkan.
  Future<void> _loadScreenshotSetting() async {
    _screenshotEnabled = await _auth.fetchScreenshotEnabled();
    ScreenSecureService.setScreenshotEnabled(_screenshotEnabled);
    if (!_disposed) notifyListeners();
  }

  /// Admin mengubah izin screenshot aplikasi (disimpan di server, semua device kena).
  Future<void> setScreenshotEnabled(bool enabled) async {
    _screenshotEnabled = enabled;
    ScreenSecureService.setScreenshotEnabled(enabled);
    if (!_disposed) notifyListeners();
    try {
      await _auth.updateScreenshotEnabled(enabled);
    } catch (e) {
      debugPrint('[AUTH] updateScreenshotEnabled error: $e');
    }
  }

  /// Bersihkan akun anonymous stale di server (fire-and-forget).
  Future<void> cleanupStaleAnonymous({int minAgeDays = 7}) {
    return _auth.cleanupStaleAnonymous(minAgeDays: minAgeDays);
  }

  /// Ambil profil user lain by UID.
  Future<UserModel?> getOtherProfile(String uid) => _auth.getProfileById(uid);
  /// Sign up dengan email — membuat akun Supabase baru.
  /// Setelah ini user perlu verifikasi email, lalu registerProfile().
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
  }) async {
    await _auth.signUpWithEmail(email, password);
    // Profile akan di-save setelah verifikasi email + login
  }

  /// Login dengan email + password.
  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmail(email, password);
    _profile = await _auth.getProfile();
    if (_profile != null) await updateFcmToken();
    notifyListeners();
  }

  /// Upgrade anonymous account ke email account. UID tetap sama.
  Future<void> linkEmailToAccount(String email, String password) async {
    await _auth.linkEmailToAccount(email, password);
    await _auth.markRegistered();
    _profile = _profile?.copyWith(isRegistered: true);
    notifyListeners();
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
    _isIdle = false;
    await _auth.resetPassword(newPassword);
    _profile = null;
    _loading = false;
    notifyListeners();
    // Jangan panggil _init() di sini — biarkan user login ulang manual.
    // _init() secara unawaited akan race condition dengan signInWithEmail.
  }

  /// Cek apakah nickname tersedia.
  Future<bool> isNicknameAvailable(String nickname) {
    return _auth.isNicknameAvailable(nickname);
  }

  Future<void> registerProfile({
    required String nickname,
    required String gender,
    required int age,
    required String country,
    required String city,
    String ipAddress = '',
  }) async {
    debugPrint('[AUTH] registerProfile START: $nickname inst=$instanceId');
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
      // lagi ada di auth.users → insert profile gagal foreign key.
      // Deteksi & buat user anon baru, lalu retry sekali.
      final msg = e.toString().toLowerCase();
      final userInvalid = msg.contains('23503') ||
          msg.contains('foreign key') ||
          msg.contains('violates') ||
          msg.contains('row-level security') ||
          msg.contains('42501');
      if (userInvalid) {
        debugPrint('[AUTH] registerProfile failed (stale anon), refreshing session: $e');
        await _auth.signOut();
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
    debugPrint('[AUTH] registerProfile DONE: ${_profile?.uid} inst=$instanceId hasListeners=$hasListeners');
    notifyListeners();
    debugPrint('[AUTH] notifyListeners called, profile=${_profile?.uid} inst=$instanceId hasListeners=$hasListeners');
    resetIdleTimer();
    updateFcmToken();
  }

  Future<void> updateProfile({int? age, String? country, String? city, String? nickname}) async {
    await _auth.updateProfile(
      age: age,
      country: country,
      city: city,
      nickname: nickname,
    );
    _profile = _profile?.copyWith(
      age: age ?? _profile?.age,
      country: country ?? _profile?.country,
      city: city ?? _profile?.city,
      nickname: nickname ?? _profile?.nickname,
    );
    notifyListeners();
  }

  /// Update IP address di server (tidak disimpan di aplikasi).
  Future<void> updateIpAddress(String ip) => _auth.updateIpAddress(ip);

  Future<void> updateAvatar(String base64) async {
    await _auth.updateAvatar(base64);
    _profile = _profile?.copyWith(avatar: base64);
    notifyListeners();
  }

  Future<void> removeAvatar() async {
    await _auth.removeAvatar();
    _profile = _profile?.copyWith(avatar: '');
    notifyListeners();
  }

  Future<void> signOut() async {
    _idleTimer?.cancel();
    _isIdle = false;
    await _auth.goOffline(); // set status offline di DB sebelum sign out
    await _auth.signOut();
    _profile = null;
    notifyListeners();
  }

  /// Call on any user interaction (tap, scroll, typing...).
  /// If user was idle, go back online. Resets the idle countdown.
  void notifyActivity() {
    if (_idleTimer == null) return; // not signed in yet
    if (_isIdle) {
      _isIdle = false;
      _auth.goOnline();
      _profile = _profile?.copyWith(status: 'online');
      notifyListeners();
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, _becomeIdle);
  }

  void resetIdleTimer() {
    _isIdle = false;
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, _becomeIdle);
  }

  Future<void> _becomeIdle() async {
    if (_disposed) return;
    _isIdle = true;
    await _auth.goIdle();
    _profile = _profile?.copyWith(status: 'idle');
    if (!_disposed) notifyListeners();
  }

  Future<void> goOnline() async {
    if (_disposed) return;
    await _auth.goOnline();
    _profile = _profile?.copyWith(status: 'online');
    if (!_disposed) notifyListeners();
    resetIdleTimer();
  }

  /// Set status idle — dipakai saat app di-background/tutup (bukan logout).
  /// User tetap tampil di menu online sebagai idle, tidak hilang.
  Future<void> goIdle() async {
    if (_disposed) return;
    _idleTimer?.cancel();
    _isIdle = true;
    await _auth.goIdle();
    _profile = _profile?.copyWith(status: 'idle');
    if (!_disposed) notifyListeners();
  }

  Future<void> goOffline() async {
    _idleTimer?.cancel();
    _isIdle = false;
    await _auth.goOffline();
    _profile = _profile?.copyWith(status: 'offline');
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    super.dispose();
  }
}
