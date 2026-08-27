import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../config/theme.dart';
import '../models/user_model.dart';
import '../providers/locale_provider.dart';
import '../core/admin_gate.dart';
import '../services/auth_service.dart';
import '../services/device_info_service.dart';
import '../services/location_service.dart';
import '../services/message_cache.dart';
import '../services/points_service.dart';
import '../services/screen_secure_service.dart';
import '../services/notification_prefs_service.dart';

// Shortcut untuk fire-and-forget.
// Tidak membungkam error: log biar kegagalan tetap terlihat di debug.
void safeUnawaited(Future<void> future) {
  future.catchError((Object e, StackTrace st) {
    debugPrint('[AUTH] safeUnawaited error: $e\n$st');
  });
}

class AuthProvider extends ChangeNotifier {
  final AuthService _auth = AuthService();
  final String instanceId =
      'AP-${DateTime.now().microsecondsSinceEpoch.toString().substring(8)}';
  UserModel? _profile;
  bool _loading = true;
  bool _disposed = false;
  bool _initInProgress = false;

  String? _error;

  Timer? _idleTimer;
  Timer? _heartbeatTimer;
  Timer? _locationTimer;
  StreamSubscription<UserModel>? _profileSub;
  StreamSubscription<AuthState>? _authStateSub;
  bool _manualSignOut = false;
  bool _isIdle = false;
  static const Duration idleTimeout = Duration(minutes: 3);
  static const Duration heartbeatInterval = Duration(seconds: 120);

  static const String _notifPrefKey = 'notif_enabled';
  bool _notificationsEnabled = true;

  // Referrer dari link share (deep link / link referal). Disimpan sementara
  // dan di-bind ke profile saat registerProfile selesai.
  static const String _referrerPrefKey = 'pending_referrer_uid';
  String? _pendingReferrer;

  bool _screenshotEnabled = true;
  bool _watermarkEnabled = false;
  bool _invisibleEnabled = false;
  bool _requireRegistration = false;
  bool _callAllEnabled = false;
  StreamSubscription<Map<String, dynamic>?>? _appSettingsSub;
  Timer? _settingsPollTimer;

  UserModel? get profile => _profile;
  bool get loading => _loading;
  String? get error => _error;
  bool get screenshotEnabled => _screenshotEnabled;
  bool get watermarkEnabled => _watermarkEnabled;
  bool get invisibleEnabled => _invisibleEnabled;
  bool get requireRegistration => _requireRegistration;
  bool get callAllEnabled => _callAllEnabled;
  bool get isSignedIn => _auth.isSignedIn;
  String? get uid => _auth.uid;
  bool get isAnonymous => _auth.isAnonymous;

  /// User sesi aktif adalah admin sungguhan (zunixe)? Dipakai untuk
  /// menampilkan/menyembunyikan seluruh UI admin di build admin — login
  /// anon/user biasa di ChatYuk Admin tetap melihat tampilan USER biasa.
  bool get isRealAdmin =>
      AdminGate.isRealAdmin(_auth.currentUser?.email);
  String? get userEmail => _auth.userEmail;
  bool get hasPassword => _auth.hasPassword;
  bool get notificationsEnabled => _notificationsEnabled;

  AuthProvider() {
    debugPrint('[AUTH-PROVIDER] CONSTRUCTED $instanceId');
    _listenAuthState();
    _init();
    loadNotificationPref();
    _loadPendingReferrer();
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
    if (referrer == uid) return;
    try {
      final ok = await _auth.bindReferrer(referrer);
      if (ok) {
        await PointsService().claimReferralReward();
        debugPrint('[AUTH] referral bind+claim OK for $referrer');
      }
    } catch (e) {
      debugPrint('[AUTH] referral bind error: $e');
    }
  }

  /// Pantau event auth Supabase. Kalau session hilang TANPA logout manual
  /// (mis. user anon dihapus di server / refresh token gagal), reset profile
  /// lokal agar tidak jadi "zombie" (user ID kosong & tidak online).
  void _listenAuthState() {
    _authStateSub = _auth.authStateChanges.listen((state) async {
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
          if (!_disposed) notifyListeners();
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
            debugPrint('[AUTH] signedOut tapi admin dipulihkan, re-init');
            await _init();
            return;
          }
        } catch (e) {
          debugPrint('[AUTH] signedOut recovery error: $e');
        }
      }
      debugPrint(
        '[AUTH] SIGNED_OUT unexpected, resetting profile (session hilang)',
      );
      _idleTimer?.cancel();
      _heartbeatTimer?.cancel();
      _locationTimer?.cancel();
      _profileSub?.cancel();
      _isIdle = false;
      _profile = null;
      if (!_disposed) notifyListeners();
    });
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
    const delays = [2, 3]; // detik antar percobaan
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        debugPrint('[AUTH] _init attempt $attempt/$maxAttempts');
        await _auth.signInAnonymously();
        debugPrint('[AUTH] signInAnonymously OK');
        _profile = await _auth.getProfile();
        debugPrint('[AUTH] getProfile -> ${_profile?.uid}');
        // Restart saat sesi dummy aktif → pulihkan state dummy + token
        // admin. Hook hanya terisi di build admin (lib/main_admin.dart).
        await AdminGate.restoreDummySession?.call();
        // Realtime: profil sendiri (poin, status, email terdaftar, dll) —
        // badge poin di profil & private chat langsung update.
        _listenProfile();
        // Setting admin (screenshot/watermark/invisible) di-fire-and-forget:
        // tidak wajib tunggu sebelum masuk app — loading cuma butuh login + profil.
        // Wajib registrasi HARUS di-await sebelum loading selesai — kalau
        // fire-and-forget, halaman pertama blink (form guest muncul dulu lalu
        // hilang saat fetch selesai). Setting lain boleh async.
        await _loadRequireRegistration();
        safeUnawaited(_loadScreenshotSetting());
        safeUnawaited(_loadCallAllSetting());
        safeUnawaited(_loadWatermarkSetting());
        safeUnawaited(_loadInvisibleSetting());
        _listenAppSettings();
        _startSettingsPolling();
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
      if (_profile != null) {
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
      _startLocationPing();
      safeUnawaited(_initLocation());
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
    _restartPresenceTimers();
    if (!_disposed) notifyListeners();
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

    // Bersihkan semua cache lama setelah login Google
    MessageCache.instance.clearAllLegacy().catchError((_) {});

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
        if (!_disposed) notifyListeners();
        return 'link_prompt';
      }
    }

    _profile = await _auth.getProfile();
    _listenProfile();
    _restartPresenceTimers();
    safeUnawaited(DeviceInfoService.instance.syncToServer());
    safeUnawaited(updateFcmToken());
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
    safeUnawaited(DeviceInfoService.instance.syncToServer());
    safeUnawaited(updateFcmToken());
    if (!_disposed) notifyListeners();
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
        if (!_disposed) notifyListeners();
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

  Future<void> _loadCallAllSetting() async {
    _callAllEnabled = await _auth.fetchCallAllEnabled();
    if (!_disposed) notifyListeners();
  }

  /// Admin: tombol call tampil ke semua user (termasuk anon/guest).
  Future<void> setCallAllEnabled(bool enabled) async {
    _callAllEnabled = enabled;
    if (!_disposed) notifyListeners();
    try {
      await _auth.updateCallAllEnabled(enabled);
    } catch (e) {
      debugPrint('[AUTH] updateCallAllEnabled error: $e');
    }
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
    _invisibleEnabled =
        setting['enabled'] == true && setting['adminUid'] == _auth.uid;
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
        safeUnawaited(_updateLocationOnOnline());
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

  /// Ambil setting admin global (wajib registrasi sebelum masuk?).
  Future<void> _loadRequireRegistration() async {
    _requireRegistration = await _auth.fetchRequireRegistration();
    if (!_disposed) notifyListeners();
  }

  /// Admin toggle wajib registrasi. Realtime: semua device ikut update
  /// lewat subscription app_settings (tidak perlu polling).
  Future<void> setRequireRegistration(bool enabled) async {
    _requireRegistration = enabled;
    if (!_disposed) notifyListeners();
    try {
      await _auth.updateRequireRegistration(enabled);
    } catch (e) {
      debugPrint('[AUTH] updateRequireRegistration error: $e');
    }
  }

  /// Subscribe realtime app_settings — toggle admin langsung berdampak di
  /// semua device (mis. wajib registrasi, screenshot, watermark, invisible).
  /// Realtime setting global via .stream() — pola yang sama (dan terbukti
  /// jalan) dengan toggle Sistem Poin di PointsProvider.watchEnabled().
  void _listenAppSettings() {
    if (_appSettingsSub != null) return;
    _appSettingsSub = _auth
        .watchGlobalSettings()
        .listen((row) {
          if (_disposed) return;
          if (row == null) return;
          debugPrint('[SETTINGS] row call_all_enabled='
              '${row['call_all_enabled']} '
              'require_registration=${row['require_registration']}');
          var changed = false;
          final nextCall = row['call_all_enabled'] == true;
          if (nextCall != _callAllEnabled) {
            _callAllEnabled = nextCall;
            changed = true;
          }
          final nextReq = row['require_registration'] == true;
          if (nextReq != _requireRegistration) {
            _requireRegistration = nextReq;
            changed = true;
          }
          if (changed && !_disposed) notifyListeners();
        }, onError: (e) => debugPrint('[SETTINGS] stream error: $e'),
           onDone: () => debugPrint('[SETTINGS] stream DONE'));
  }

  /// Polling cadangan bila websocket realtime mati — max delay 10 detik.
  void _startSettingsPolling() {
    _settingsPollTimer?.cancel();
    _settingsPollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_disposed || !_auth.isSignedIn) return;
      try {
        final callAll = await _auth.fetchCallAllEnabled();
        var changed = false;
        if (callAll != _callAllEnabled) {
          _callAllEnabled = callAll;
          changed = true;
        }
        final reqReg = await _auth.fetchRequireRegistration();
        if (reqReg != _requireRegistration) {
          _requireRegistration = reqReg;
          changed = true;
        }
        debugPrint('[SETTINGS-POLL] callAll=$callAll '
            'cur=$_callAllEnabled changed=$changed');
        if (changed && !_disposed) notifyListeners();
      } catch (e) {
        debugPrint('[SETTINGS-POLL] error: $e');
      }
    });
  }

  /// Bersihkan presence room yang basi di server (fire-and-forget).
  Future<void> cleanupStalePresence({int minAgeMinutes = 10}) {
    return _auth.cleanupStalePresence(minAgeMinutes: minAgeMinutes);
  }

  /// Ambil profil user lain by UID.
  Future<UserModel?> getOtherProfile(String uid) => _auth.getProfileById(uid);

  /// Sign up dengan email — membuat akun Supabase baru (butuh verifikasi
  /// email). Return true bila session sudah aktif (auto-confirm), false bila
  /// perlu verifikasi OTP dulu.
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
    if (!_disposed) notifyListeners();
  }

  /// Upgrade anonymous account ke email account. UID tetap sama.
  Future<void> linkEmailToAccount(String email, String password) async {
    await _auth.linkEmailToAccount(email, password);
    await _auth.markRegistered();
    _profile = _profile?.copyWith(isRegistered: true);
    // Kasih bonus +100 poin untuk register email
    _claimRegisterBonus();
    safeUnawaited(updateFcmToken());
    if (!_disposed) notifyListeners();
  }

  Future<void> _claimDailyPoints() async {
    try {
      final pointsService = PointsService();
      final enabled = await pointsService.fetchEnabled();
      if (!enabled) return;
      final old = _profile?.points ?? 0;
      final res = await pointsService.dailyLoginBonus();
      final newPoints = (res['points'] as num?)?.toInt() ?? old;
      _profile = _profile?.copyWith(points: newPoints);
      debugPrint(
        '[AUTH] dailyLoginBonus: $old -> $newPoints (streak ${res['streak']})',
      );
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
    _locationTimer?.cancel();
    _isIdle = false;
    _manualSignOut = true;
    try {
      await _auth.resetPassword(newPassword);
    } finally {
      _manualSignOut = false;
    }
    _profile = null;
    _loading = false;
    if (!_disposed) notifyListeners();
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
      final userInvalid =
          msg.contains('23503') ||
          msg.contains('foreign key') ||
          msg.contains('violates') ||
          msg.contains('row-level security') ||
          msg.contains('42501');
      if (userInvalid) {
        debugPrint(
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
    debugPrint(
      '[AUTH] registerProfile DONE: ${_profile?.uid} inst=$instanceId hasListeners=$hasListeners',
    );
    if (!_disposed) notifyListeners();
    debugPrint(
      '[AUTH] notifyListeners called, profile=${_profile?.uid} inst=$instanceId hasListeners=$hasListeners',
    );
    resetIdleTimer();
    _restartPresenceTimers();
    updateFcmToken();
    // Ikat referrer (bila ada) — sekali saja, setelah profil terdaftar.
    _bindAndClaimReferrer();
  }

  Future<void> updateProfile({
    int? age,
    String? country,
    String? city,
    String? nickname,
  }) async {
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
    _manualSignOut = true;
    try {
      _idleTimer?.cancel();
      _heartbeatTimer?.cancel();
      _locationTimer?.cancel();
      _profileSub?.cancel();
      _isIdle = false;
      await _auth.goOffline();
      await _auth.signOut();
      _profile = null;
      if (!_disposed) notifyListeners();
    } finally {
      _manualSignOut = false;
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
    debugPrint('[AUTH] becomeDummy done, uid=$_auth.uid, '
        'flag=${_auth.dummySessionActive}');
    await reloadProfile();
  }

  /// Kembali ke akun admin dari sesi dummy. Return false jika token admin
  /// kedaluwarsa (perlu login manual).
  Future<bool> backToAdmin() async {
    final impl = AdminGate.backToAdminImpl;
    if (impl == null) return false;
    final ok = await impl();
    if (ok) _auth.markDummyState(active: false);
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
      debugPrint('[AUTH] reloadProfile lite -> ${lite?.uid} ${lite?.nickname}');
      if (lite != null && !_disposed) {
        _profile = lite;
        notifyListeners();
      }
    } catch (e) {
      // Jaringan flaky — jangan biarkan exception menggagalkan swap.
      debugPrint('[AUTH] reloadProfile lite FAILED: $e');
    }
    // Tahap lengkap: avatar (cache per path, biasanya instan).
    try {
      _profile = await _auth.getProfile();
      debugPrint('[AUTH] reloadProfile full -> ${_profile?.uid}');
    } catch (e) {
      debugPrint('[AUTH] reloadProfile full FAILED: $e');
    }
    _listenProfile();
    _restartPresenceTimers();
    // Update FCM token untuk sesi yang baru aktif (swap dummy ⇄ admin) —
    // tanpa ini, token FCM profil dummy tidak ter-update ke device fisik
    // ini sehingga push call/chat ke dummy ditolak (NotRegistered).
    if (_profile != null) safeUnawaited(updateFcmToken());
    if (!_disposed) notifyListeners();
  }

  /// Call on any user interaction (tap, scroll, typing...).
  /// If user was idle, go back online. Resets the idle countdown.
  void notifyActivity() {
    if (_idleTimer == null) return; // not signed in yet
    if (dummySessionActive) return; // status dummy dikontrol admin panel
    if (_invisibleEnabled) return; // invisible → jangan pernah kembali online
    if (_isIdle) {
      _isIdle = false;
      _auth.goOnline();
      _profile = _profile?.copyWith(status: 'online');
      safeUnawaited(_updateLocationOnOnline());
      notifyListeners();
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
    if (dummySessionActive) return; // status dummy dikontrol admin panel
    if (_invisibleEnabled) return;
    _isIdle = true;
    await _auth.goIdle();
    _profile = _profile?.copyWith(status: 'idle');
    if (!_disposed) notifyListeners();
  }

  Future<void> goOnline() async {
    if (_disposed) return;
    if (dummySessionActive) return; // status dummy dikontrol admin panel
    if (_invisibleEnabled) return; // invisible → jangan pernah online
    await _auth.goOnline();
    _profile = _profile?.copyWith(status: 'online');
    if (!_disposed) notifyListeners();
    resetIdleTimer();
    safeUnawaited(_updateLocationOnOnline());
  }

  /// Set status idle — dipakai saat app di-background/tutup (bukan logout).
  /// User tetap tampil di menu online sebagai idle, tidak hilang.
  Future<void> goIdle() async {
    if (_disposed) return;
    if (dummySessionActive) return; // status dummy dikontrol admin panel
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

  /// Heartbeat berkala: update last_seen di server tiap 120 detik.
  /// Kalau app di-kill/force-stop, heartbeat berhenti dan last_seen
  /// jadi basi sehingga admin bisa menandai user offline.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (_disposed) return;
      safeUnawaited(_auth.updateLastSeen());
    });
  }

  /// Update lokasi berkala (5 menit) saat app aktif — pin di peta admin
  /// dan daftar orang sekitar selalu segar. GPS dipakai kalau izin sudah
  /// ada, else perkiraan IP. Gagal diam-diam (tidak mengganggu apapun).
  void _startLocationPing() {
    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_disposed || dummySessionActive) return;
      safeUnawaited(LocationService().updateMyLocation());
    });
  }

  /// Update + catat history posisi saat status berubah jadi online
  /// (idle→online, invisible→online, panggil goOnline). Fire-and-forget,
  /// GPS dipakai kalau izin ada, else perkiraan IP.
  Future<void> _updateLocationOnOnline() async {
    if (_disposed || dummySessionActive) return;
    try {
      await LocationService().updateMyLocation();
    } catch (e) {
      debugPrint('[AUTH] location on online error: $e');
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
      final loc = LocationService();
      await loc.requestPermission();
      // Kalau lokasi TIDAK tersimpan sama sekali (GPS & IP gagal) →
      // besar kemungkinan izin presisi (FINE) belum diberikan dan
      // Android tidak mau menampilkan dialog lagi → arahkan ke Settings.
      final source = await loc.updateMyLocation();
      if (source == null) {
        final prefs = await SharedPreferences.getInstance();
        final prompted = prefs.getBool('location_settings_prompted') ?? false;
        if (!prompted && !_disposed) {
          await prefs.setBool('location_settings_prompted', true);
          _promptLocationSettings();
        }
      }
    } catch (e) {
      debugPrint('[AUTH] _initLocation error: $e');
    }
  }

  /// Dialog sekali: arahkan ke Pengaturan kalau lokasi presisi mati.
  void _promptLocationSettings() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return;
    final s = ctx.read<LocaleProvider>().s;
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
    _locationTimer?.cancel();
    _profileSub?.cancel();
    _authStateSub?.cancel();
    _appSettingsSub?.cancel();
    _settingsPollTimer?.cancel();
    super.dispose();
  }
}
