import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/message_cache.dart';
import '../services/points_service.dart';
import '../services/screen_secure_service.dart';

// Shortcut untuk fire-and-forget.
// Tidak membungkam error: log biar kegagalan tetap terlihat di debug.
void safeUnawaited(Future<void> future) {
  future.catchError((Object e, StackTrace st) {
    debugPrint('[AUTH] safeUnawaited error: $e\n$st');
  });
}

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
  final String instanceId = 'AP-${DateTime.now().microsecondsSinceEpoch.toString().substring(8)}';
  UserModel? _profile;
  bool _loading = true;
  bool _disposed = false;
  bool _initInProgress = false;

  String? _error;

  Timer? _idleTimer;
  Timer? _heartbeatTimer;
  StreamSubscription<UserModel>? _profileSub;
  bool _isIdle = false;
  static const Duration idleTimeout = Duration(minutes: 3);
  static const Duration heartbeatInterval = Duration(seconds: 60);

  static const String _notifPrefKey = 'notif_enabled';
  bool _notificationsEnabled = true;

  bool _screenshotEnabled = true;
  bool _watermarkEnabled = false;
  bool _invisibleEnabled = false;

  UserModel? get profile => _profile;
  bool get loading => _loading;
  String? get error => _error;
  bool get screenshotEnabled => _screenshotEnabled;
  bool get watermarkEnabled => _watermarkEnabled;
  bool get invisibleEnabled => _invisibleEnabled;
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
    // Auto-retry dengan backoff: jaringan (DNS/connectivity) sering gagal
    // sesaat, apalagi pas baru connect WiFi atau ganti user. Jangan langsung
    // tampilkan layar error — coba ulang dulu beberapa kali.
    const maxAttempts = 2;
    const delays = [3, 5]; // detik antar percobaan
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        debugPrint('[AUTH] _init attempt $attempt/$maxAttempts');
        await _auth.signInAnonymously();
        debugPrint('[AUTH] signInAnonymously OK');
        _profile = await _auth.getProfile();
        debugPrint('[AUTH] getProfile -> ${_profile?.uid}');
        // Realtime: profil sendiri (poin, status, email terdaftar, dll) —
        // badge poin di profil & private chat langsung update.
        _listenProfile();
        // Terapkan setting admin: izinkan screenshot aplikasi atau tidak
        await _loadScreenshotSetting();
        // Terapkan setting admin: watermark forensik foto view-once
        await _loadWatermarkSetting();
        // Terapkan setting admin: invisible (tidak muncul di daftar online)
        await _loadInvisibleSetting();
        lastError = null;
        break;
      } catch (e) {
        lastError = e;
        debugPrint('[AUTH] _init attempt $attempt failed: $e');
        if (_disposed) return;
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: delays[attempt - 1]));
          if (_disposed) return;
        }
      }
    }
    if (lastError != null) {
      debugPrint('[AUTH] _init ERROR: $lastError');
      _error = lastError.toString();
    } else {
      // FCM token & cleanup di-fire-and-forget — tidak block loading screen
      if (_profile != null) safeUnawaited(updateFcmToken());
      safeUnawaited(cleanupStaleAnonymous());
      if (_disposed) return;
      _startHeartbeat();
      // Daily login bonus poin
      safeUnawaited(_claimDailyPoints());
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
    _listenProfile();
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

    // Bersihkan semua cache lama setelah login Google
    MessageCache.instance.clearAllLegacy().catchError((_) {});

    // Cek apakah email ini sudah punya profile di akun lain
    if (googleEmail != null) {
      final existing = await _auth.checkEmailExists(googleEmail);
      print('[AUTH-PROVIDER] checkEmailExists result=$existing');
      if (existing != null) {
        _pendingLinkProfileId = existing['profile_id'] as String?;
        _pendingLinkNickname = existing['nickname'] as String?;
        _profile = await _auth.getProfile();
        _listenProfile();
        if (!_disposed) notifyListeners();
        return 'link_prompt';
      }
    }

    _profile = await _auth.getProfile();
    print('[AUTH-PROVIDER] getProfile after google -> ${_profile?.uid}');
    _listenProfile();
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
    _listenProfile();
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

  /// Simpan daftar hashtag profil (diupdate lokal + server).
  Future<void> updateHashtags(List<String> hashtags) async {
    await _auth.updateHashtags(hashtags);
    _profile = _profile?.copyWith(hashtags: hashtags);
    if (!_disposed) notifyListeners();
  }

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

  /// Ambil setting admin global (watermark forensik view-once?).
  Future<void> _loadWatermarkSetting() async {
    _watermarkEnabled = await _auth.fetchWatermarkEnabled();
    if (!_disposed) notifyListeners();
  }

  /// Admin mengaktifkan/menonaktifkan watermark forensik foto view-once.
  Future<void> setWatermarkEnabled(bool enabled) async {
    _watermarkEnabled = enabled;
    if (!_disposed) notifyListeners();
    try {
      await _auth.updateWatermarkEnabled(enabled);
    } catch (e) {
      debugPrint('[AUTH] updateWatermarkEnabled error: $e');
    }
  }

  /// Ambil setting admin global (invisible — tidak muncul di daftar online).
  /// Hanya admin dengan UID yang tercatat yang ikut jadi invisible.
  Future<void> _loadInvisibleSetting() async {
    final setting = await _auth.fetchInvisibleSetting();
    _invisibleEnabled = setting['enabled'] == true && setting['adminUid'] == _auth.uid;
    if (_invisibleEnabled) {
      _profile = _profile?.copyWith(status: 'invisible');
      safeUnawaited(_auth.goInvisible());
    }
    if (!_disposed) notifyListeners();
  }

  /// Re-sync setting invisible (dipanggil saat app resumed). Supaya device
  /// kedua ikut tahu toggle dari device pertama dan tidak menimpa balik.
  Future<void> resyncInvisible() async {
    final setting = await _auth.fetchInvisibleSetting();
    final enabled = setting['enabled'] == true && setting['adminUid'] == _auth.uid;
    if (enabled == _invisibleEnabled) return;
    _invisibleEnabled = enabled;
    if (enabled) {
      _idleTimer?.cancel();
      _isIdle = false;
      await _auth.goInvisible();
      _profile = _profile?.copyWith(status: 'invisible');
    }
    if (!_disposed) notifyListeners();
  }

  /// Admin toggle invisible. ON → status invisible (user lain lihat offline,
  /// tidak muncul di daftar online; admin sendiri lihat "invisible").
  /// OFF → kembali online. Hanya tersedia untuk admin.
  Future<void> setInvisibleEnabled(bool enabled) async {
    _invisibleEnabled = enabled;
    if (!_disposed) notifyListeners();
    try {
      await _auth.updateInvisibleEnabled(enabled);
      if (enabled) {
        _idleTimer?.cancel();
        _isIdle = false;
        await _auth.goInvisible();
        _profile = _profile?.copyWith(status: 'invisible');
      } else {
        await _auth.goOnline();
        _profile = _profile?.copyWith(status: 'online');
        resetIdleTimer();
      }
    } catch (e) {
      debugPrint('[AUTH] updateInvisibleEnabled error: $e');
    }
    if (!_disposed) notifyListeners();
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
    _listenProfile();
    if (_profile != null) await updateFcmToken();
    if (!_disposed) notifyListeners();
  }

  /// Upgrade anonymous account ke email account. UID tetap sama.
  Future<void> linkEmailToAccount(String email, String password) async {
    await _auth.linkEmailToAccount(email, password);
    await _auth.markRegistered();
    _profile = _profile?.copyWith(isRegistered: true);
    // Kasih bonus +100 poin untuk register email
    _claimRegisterBonus();
    if (!_disposed) notifyListeners();
  }

  Future<void> _claimDailyPoints() async {
    try {
      final pointsService = PointsService();
      final enabled = await pointsService.fetchEnabled();
      if (!enabled) return;
      final old = _profile?.points ?? 0;
      final newPoints = await pointsService.dailyLoginBonus();
      _profile = _profile?.copyWith(points: newPoints);
      debugPrint('[AUTH] dailyLoginBonus: $old -> $newPoints');
      // Toast akan ditampilkan oleh PointsProvider di screen yang aktif
      // via checkAndShowOnlineToast / PointsProvider listener
    } catch (e) {
      debugPrint('[AUTH] dailyLoginBonus error: $e');
    }
  }

  Future<void> _claimRegisterBonus() async {
    try {
      final pointsService = PointsService();
      final enabled = await pointsService.fetchEnabled();
      if (!enabled) return;
      final newPoints = await pointsService.registerBonus();
      _profile = _profile?.copyWith(points: newPoints);
      debugPrint('[AUTH] registerBonus -> $newPoints');
    } catch (e) {
      debugPrint('[AUTH] registerBonus error: $e');
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
    _isIdle = false;
    await _auth.resetPassword(newPassword);
    _profile = null;
    _loading = false;
    if (!_disposed) notifyListeners();
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
    if (!_disposed) notifyListeners();
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
    if (!_disposed) notifyListeners();
  }

  /// Update IP address di server (tidak disimpan di aplikasi).
  Future<void> updateIpAddress(String ip) => _auth.updateIpAddress(ip);

  Future<void> updateAvatar(String base64) async {
    await _auth.updateAvatar(base64);
    _profile = _profile?.copyWith(avatar: base64);
    if (!_disposed) notifyListeners();
  }

  Future<void> removeAvatar() async {
    await _auth.removeAvatar();
    _profile = _profile?.copyWith(avatar: '');
    if (!_disposed) notifyListeners();
  }

  Future<void> signOut() async {
    _idleTimer?.cancel();
    _heartbeatTimer?.cancel();
    _profileSub?.cancel();
    _isIdle = false;
    await _auth.goOffline();
    await _auth.signOut();
    _profile = null;
    if (!_disposed) notifyListeners();
  }

  /// Call on any user interaction (tap, scroll, typing...).
  /// If user was idle, go back online. Resets the idle countdown.
  void notifyActivity() {
    if (_idleTimer == null) return; // not signed in yet
    if (_invisibleEnabled) return; // invisible → jangan pernah kembali online
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
    if (_invisibleEnabled) return;
    _idleTimer = Timer(idleTimeout, _becomeIdle);
  }

  Future<void> _becomeIdle() async {
    if (_disposed) return;
    if (_invisibleEnabled) return;
    _isIdle = true;
    await _auth.goIdle();
    _profile = _profile?.copyWith(status: 'idle');
    if (!_disposed) notifyListeners();
  }

  Future<void> goOnline() async {
    if (_disposed) return;
    if (_invisibleEnabled) return; // invisible → jangan pernah online
    await _auth.goOnline();
    _profile = _profile?.copyWith(status: 'online');
    if (!_disposed) notifyListeners();
    resetIdleTimer();
  }

  /// Set status idle — dipakai saat app di-background/tutup (bukan logout).
  /// User tetap tampil di menu online sebagai idle, tidak hilang.
  Future<void> goIdle() async {
    if (_disposed) return;
    if (_invisibleEnabled) return; // invisible → tetap offline
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

  /// Heartbeat berkala: update last_seen di server tiap 60 detik.
  /// Kalau app di-kill/force-stop, heartbeat berhenti dan last_seen
  /// jadi basi sehingga admin bisa menandai user offline.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (_disposed) return;
      safeUnawaited(_auth.updateLastSeen());
    });
  }

  void _listenProfile() {
    _profileSub?.cancel();
    _profileSub = _auth.onMyProfileUpdates().listen((updated) {
      if (_disposed) return;
      _profile = updated;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _idleTimer?.cancel();
    _heartbeatTimer?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }
}
