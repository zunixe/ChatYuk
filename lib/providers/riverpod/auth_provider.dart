import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../main.dart';
import '../../config/theme.dart';
import '../../config/fonts.dart';
import '../../models/user_model.dart';
import '../../models/user_photo.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../core/admin_gate.dart';
import '../../services/avatar_service.dart';
import '../../services/auth_service.dart';
export '../../services/auth_service.dart'
    show EmailNotRegisteredException, EmailAlreadyRegisteredException;
import '../../services/chat_service.dart';
import '../../services/tiktok_service.dart';
import '../../services/device_info_service.dart';
import '../../services/points_service.dart';
import '../../services/location_service.dart';
import '../../core/cache/message_cache.dart';
import '../../core/media/image_cache_hygiene.dart';
import '../../services/realtime_hub.dart';
import '../../services/rt_resilient.dart';
import '../../core/screen_secure_service.dart';
import '../../services/storage_photo_service.dart';
import '../../services/notification_prefs_service.dart';
import '../../utils.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

// Shortcut untuk fire-and-forget.
// Tidak membungkam error: log biar kegagalan tetap terlihat di debug.
void safeUnawaited(Future<void> future) {
  future.catchError((Object e, StackTrace st) {
    dlog('[AUTH] safeUnawaited error: $e\n$st');
  });
}

/// State auth (immutable — yang di-watch widget).
class AuthData {
  final UserModel? profile;
  final bool loading;
  final String? error;
  final bool signingOut;
  final String? uid;
  final bool isSignedIn;
  final bool isAnonymous;
  final bool dummySessionActive;
  final bool emailConfirmed;
  final String? userEmail;
  final bool hasPassword;
  final bool isRealAdmin;
  final bool anonBlocked;
  final bool anonTimelineBlocked;
  final bool screenshotEnabled;
  final bool watermarkEnabled;
  final bool invisibleEnabled;
  final bool reengageEnabled;
  final bool requireRegistration;
  final bool callAllEnabled;
  final bool callAnonEnabled;
  final String appFontFamily;
  final List<String> excludedDevices;
  final bool notificationsEnabled;

  const AuthData({
    this.profile,
    this.loading = true,
    this.error,
    this.signingOut = false,
    this.uid,
    this.isSignedIn = false,
    this.isAnonymous = false,
    this.dummySessionActive = false,
    this.emailConfirmed = false,
    this.userEmail,
    this.hasPassword = false,
    this.isRealAdmin = false,
    this.anonBlocked = false,
    this.anonTimelineBlocked = false,
    this.screenshotEnabled = true,
    this.watermarkEnabled = false,
    this.invisibleEnabled = false,
    this.reengageEnabled = true,
    this.requireRegistration = false,
    this.callAllEnabled = false,
    this.callAnonEnabled = false,
    this.appFontFamily = 'default',
    this.excludedDevices = const [],
    this.notificationsEnabled = true,
  });

  @override
  bool operator ==(Object other) =>
      other is AuthData &&
      other.profile == profile &&
      other.loading == loading &&
      other.error == error &&
      other.signingOut == signingOut &&
      other.uid == uid &&
      other.isSignedIn == isSignedIn &&
      other.isAnonymous == isAnonymous &&
      other.dummySessionActive == dummySessionActive &&
      other.emailConfirmed == emailConfirmed &&
      other.userEmail == userEmail &&
      other.hasPassword == hasPassword &&
      other.isRealAdmin == isRealAdmin &&
      other.anonBlocked == anonBlocked &&
      other.anonTimelineBlocked == anonTimelineBlocked &&
      other.screenshotEnabled == screenshotEnabled &&
      other.watermarkEnabled == watermarkEnabled &&
      other.invisibleEnabled == invisibleEnabled &&
      other.reengageEnabled == reengageEnabled &&
      other.requireRegistration == requireRegistration &&
      other.callAllEnabled == callAllEnabled &&
      other.callAnonEnabled == callAnonEnabled &&
      other.appFontFamily == appFontFamily &&
      other.notificationsEnabled == notificationsEnabled &&
      listEquals(other.excludedDevices, excludedDevices);

  @override
  int get hashCode => Object.hashAll([
        profile,
        loading,
        error,
        signingOut,
        uid,
        isSignedIn,
        isAnonymous,
        dummySessionActive,
        emailConfirmed,
        userEmail,
        hasPassword,
        isRealAdmin,
        anonBlocked,
        anonTimelineBlocked,
        screenshotEnabled,
        watermarkEnabled,
        invisibleEnabled,
        reengageEnabled,
        requireRegistration,
        callAllEnabled,
        callAnonEnabled,
        appFontFamily,
        notificationsEnabled,
        Object.hashAll(excludedDevices),
      ]);
}

/// Sesi + profil + settings global (Riverpod). Migrasi dari ChangeNotifier.
/// Global (persist sepanjang sesi).
class AuthNotifier extends Notifier<AuthData> {
  final AuthService _auth;
  final bool _autoInit;
  final String instanceId =
      'AP-${DateTime.now().microsecondsSinceEpoch.toString().substring(8)}';
  UserModel? _profile;
  bool _loading = true;
  bool _disposed = false;
  bool _initInProgress = false;

  /// True selagi proses keluar berjalan (logout / hapus akun). Dipakai gate
  /// root supaya transisi keluar LANGSUNG ke EntryScreen — tanpa sempat
  /// merender `_ProfileGate`/MainNav sekejap (flash "halaman lain").
  bool _signingOut = false;
  bool get signingOut => _signingOut;

  String? _error;

  Timer? _idleTimer;
  Timer? _heartbeatTimer;
  Timer? _locationTimer;
  StreamSubscription<({UserModel model, Set<String> keys})>?
  _profileSub;
  StreamSubscription<AuthState>? _authStateSub;
  bool _manualSignOut = false;
  bool _isIdle = false;
  static const Duration idleTimeout = Duration(minutes: 3);
  static const Duration heartbeatInterval = Duration(seconds: 240);

  static const String _notifPrefKey = 'notif_enabled';
  bool _notificationsEnabled = true;

  // Referrer dari link share (deep link / link referal). Disimpan sementara
  // dan di-bind ke profile saat registerProfile selesai.
  static const String _referrerPrefKey = 'pending_referrer_uid';
  String? _pendingReferrer;

  bool _screenshotEnabled = true;
  bool _watermarkEnabled = false;
  bool _invisibleEnabled = false;
  bool _reengageEnabled = true;
  bool _requireRegistration = false;
  bool _callAllEnabled = false;
  bool _callAnonEnabled = false;
  // Font global (key katalog AppFonts) — 'default' = Poppins + Roboto.
  String _appFontFamily = AppFonts.defaultKey;
  // Daftar install_id yang di-exclude admin dari ringkasan & daftar
  // perangkat (fitur khusus admin, sinkron via app_settings.global).
  List<String> _excludedDevices = [];
  StreamSubscription<Map<String, dynamic>?>? _appSettingsSub;
  Timer? _settingsPollTimer;

  bool get screenshotEnabled => _screenshotEnabled;
  bool get watermarkEnabled => _watermarkEnabled;
  bool get invisibleEnabled => _invisibleEnabled;
  bool get reengageEnabled => _reengageEnabled;
  bool get requireRegistration => _requireRegistration;
  bool get callAllEnabled => _callAllEnabled;
  bool get callAnonEnabled => _callAnonEnabled;
  String get appFontFamily => _appFontFamily;
  List<String> get excludedDevices => List.unmodifiable(_excludedDevices);
  bool isDeviceExcluded(String? installId) =>
      installId != null &&
      installId.isNotEmpty &&
      _excludedDevices.contains(installId);

  UserModel? get profile => _profile;
  bool get loading => _loading;
  String? get error => _error;
  bool get isSignedIn => _auth.isSignedIn;
  String? get uid => _auth.uid;
  bool get isAnonymous => _auth.isAnonymous;

  /// Soft gate anon: registrasi wajib ON + sesi ini anon → tulis diblokir
  /// (server RLS juga menegakkan). Stream settings realtime → getter ini
  /// berubah otomatis tanpa restart app. Sesi dummy (admin jadi anon)
  /// dikecualikan — server juga bypass via admin_dummy_uids().
  bool get anonBlocked =>
      _requireRegistration && _auth.isAnonymous && !_auth.dummySessionActive;

  /// Gerbang Timeline/sosial ABSOLUT (selalu aktif, tak tergantung toggle
  /// `require_registration`): akun anon (belum registrasi) TIDAK bisa melihat
  /// Timeline. Server menegakkan via `list_posts` → raise 'ANON_DISABLED'.
  /// Dipakai UI supaya anon melihat dialog "daftar dulu" (bukan layar error
  /// retry dari RPC yang memang pasti gagal). Bypass: dummy & admin (server
  /// juga bypass via admin_dummy_uids).
  bool get anonTimelineBlocked =>
      _auth.isAnonymous && !dummySessionActive && !isRealAdmin;

  /// User sesi aktif adalah admin sungguhan (zunixe)? Dipakai untuk
  /// menampilkan/menyembunyikan seluruh UI admin di build admin — login
  /// anon/user biasa di ChatYuk Admin tetap melihat tampilan USER biasa.
  bool get isRealAdmin => AdminGate.isRealAdmin(_auth.currentUser?.email);
  String? get userEmail => _auth.userEmail;

  /// True bila profil aktif memakai nickname terlarang dan bukan admin.
  /// Dipakai gerbang login (blokir masuk app) + matikan presence supaya
  /// akun banned tidak tampil online / di orang-sekitar.
  bool get isProfileBanned =>
      _profile != null && !isRealAdmin && isBannedNickname(_profile!.nickname);
  bool get hasPassword => _auth.hasPassword;
  Future<bool> fetchHasPassword() => _auth.fetchHasPassword();
  bool get hasPasswordSync => _auth.hasPassword;
  Future<void> refreshHasPassword() async {
    await _auth.fetchHasPassword();
    _emit();
  }

  bool get notificationsEnabled => _notificationsEnabled;

  AuthNotifier({AuthService? authService, bool autoInit = true})
      : _auth = authService ?? AuthService(),
        _autoInit = autoInit;

  @override
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
          _requireRegistration && _auth.isAnonymous && !_auth.dummySessionActive,
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
      dlog('[AUTH] SIGNED_OUT unexpected, resetting profile (session hilang)');
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
    }, onError: (e) {
      dlog('[AUTH] authState stream error: $e');
    });
  }

  /// Hook opsional: dipasang root widget untuk membersihkan resource
  /// chat saat signedOut TIDAK lewat tombol logout (sesi mati).
  void Function()? _onSignedOut;
  set onSignedOut(void Function()? cb) => _onSignedOut = cb;

  /// Cache profil sendiri (SharedPreferences): cold start dengan sesi
  /// existing langsung tampil MainNav dari disk, revalidasi network di
  /// belakang. Key per-uid supaya ganti akun tidak tertukar.
  static const _profileCachePrefix = 'cached_profile_v1_';

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
  Future<void> preloadProfileCache(String uid) => _auth.preloadProfileCache(uid);

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
    final s = ProviderScope.containerOf(ctx, listen: false).read(localeProvider).s;
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
    _profileSub = _auth.onMyProfileUpdates().listen((rec) {
      if (_disposed) return;
      _applyProfileUpdate(rec.model, presentKeys: rec.keys);
    }, onError: (e) {
      dlog('[AUTH] profile stream error: $e');
    });
  }

  /// Gabung event profil dengan state lokal: hanya kolom yang ADA di
  /// payload event yang diambil; sisanya dipertahankan dari state saat ini.
  ///
  /// Latar: payload realtime tidak memuat kolom yang di-revoke dari role
  /// authenticated (about/status/avatar/last_seen/dll). Replace mentah
  /// menimpa kolom-kolom itu dengan default kosong (gejala: Tentang tampil
  /// lalu hilang lagi). Murni supaya bisa di-unit-test.
  @visibleForTesting
  static UserModel mergeProfileEvent({
    required UserModel? current,
    required UserModel event,
    required Set<String> presentKeys,
  }) {
    final cur = current;
    if (cur == null) return event;
    T pick<T>(String key, T ev, T curV) =>
        presentKeys.contains(key) ? ev : curV;
    return event.copyWith(
      nickname: pick('nickname', event.nickname, cur.nickname),
      gender: pick('gender', event.gender, cur.gender),
      age: pick('age', event.age, cur.age),
      country: pick('country', event.country, cur.country),
      city: pick('city', event.city, cur.city),
      ipAddress: pick('ipAddress', event.ipAddress, cur.ipAddress),
      status: pick('status', event.status, cur.status),
      avatar: pick('avatar', event.avatar, cur.avatar),
      isRegistered: pick(
        'isRegistered',
        event.isRegistered,
        cur.isRegistered,
      ),
      lastSeen: pick('lastSeen', event.lastSeen, cur.lastSeen),
      hashtags: pick('hashtags', event.hashtags, cur.hashtags),
      points: pick('points', event.points, cur.points),
      shareLocation: pick(
        'shareLocation',
        event.shareLocation,
        cur.shareLocation,
      ),
      followersCount: pick(
        'followersCount',
        event.followersCount,
        cur.followersCount,
      ),
      followingCount: pick(
        'followingCount',
        event.followingCount,
        cur.followingCount,
      ),
      subscriberCount: pick(
        'subscriberCount',
        event.subscriberCount,
        cur.subscriberCount,
      ),
      subscriptionPrice: pick(
        'subscriptionPrice',
        event.subscriptionPrice,
        cur.subscriptionPrice,
      ),
      friendsCount: pick(
        'friendsCount',
        event.friendsCount,
        cur.friendsCount,
      ),
      email: pick('email', event.email, cur.email),
      about: pick('about', event.about, cur.about),
      // needsOnboarding TIDAK ada di payload realtime (kolom non-publik) →
      // selalu pertahankan nilai state lokal. Tanpa ini, event profil apa
      // pun (status/points) menimpa flag jadi default false → user anon
      // yang baru dibuat trigger langsung lolos ke MainNav.
      needsOnboarding: cur.needsOnboarding,
    );
  }

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

final authProvider = NotifierProvider<AuthNotifier, AuthData>(AuthNotifier.new);
