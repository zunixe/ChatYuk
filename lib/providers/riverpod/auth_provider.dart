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
import '../../models/auth_data.dart';
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

part 'auth_provider_init.dart';
part 'auth_provider_settings.dart';
part 'auth_provider_actions.dart';

const Duration idleTimeout = Duration(minutes: 3);
const Duration heartbeatInterval = Duration(seconds: 240);
const String _referrerPrefKey = 'pending_referrer_uid';
const String _profileCachePrefix = 'cached_profile_v1_';
const String _notifPrefKey = 'notif_enabled';

// Shortcut untuk fire-and-forget.
// Tidak membungkam error: log biar kegagalan tetap terlihat di debug.
void safeUnawaited(Future<void> future) {
  future.catchError((Object e, StackTrace st) {
    dlog('[AUTH] safeUnawaited error: $e\n$st');
  });
}

/// State auth (immutable — yang di-watch widget).

/// Sesi + profil + settings global (Riverpod). Migrasi dari ChangeNotifier.
/// Global (persist sepanjang sesi).
/// State + field bersama AuthNotifier — dipakai mixin per-domain (file `part`).
UserModel mergeProfileEvent({
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
    isRegistered: pick('isRegistered', event.isRegistered, cur.isRegistered),
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
    friendsCount: pick('friendsCount', event.friendsCount, cur.friendsCount),
    email: pick('email', event.email, cur.email),
    about: pick('about', event.about, cur.about),
    // needsOnboarding TIDAK ada di payload realtime (kolom non-publik) →
    // selalu pertahankan nilai state lokal. Tanpa ini, event profil apa
    // pun (status/points) menimpa flag jadi default false → user anon
    // yang baru dibuat trigger langsung lolos ke MainNav.
    needsOnboarding: cur.needsOnboarding,
  );
}

abstract class _AuthBase extends Notifier<AuthData> {
  _AuthBase(AuthService? authService, bool autoInit)
    : _auth = authService ?? AuthService(),
      _autoInit = autoInit;

  /// Kontrak lintas-mixin (didefinisikan di mixin per-domain).
  bool get dummySessionActive;
  void _emit();
  Future<void> _bindAndClaimReferrer();
  void _syncTikTok({TikTokEvent? event});
  Future<void> updateFcmToken();
  Future<void> _saveCachedProfile(UserModel p);
  void _disposeAll();
  Future<void> _claimDailyPoints();
  Future<int> _claimWelcome(String kind);
  Future<void> _initLocation();
  void _listenAppSettings();
  void _listenProfile();
  Future<void> _loadExcludedDevices();
  Future<void> _loadGlobalSettings();
  void _restartPresenceTimers();
  void _startHeartbeat();
  void _startLocationPing();
  void _startSettingsPolling();
  Future<void> _updateLocationOnOnline();
  Future<void> cleanupStaleAnonymous({int minAgeDays});
  void resetIdleTimer();

  late final AuthService _auth;
  late final bool _autoInit;
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
  StreamSubscription<({UserModel model, Set<String> keys})>? _profileSub;
  StreamSubscription<AuthState>? _authStateSub;
  bool _manualSignOut = false;
  bool _isIdle = false;

  bool _notificationsEnabled = true;

  // Referrer dari link share (deep link / link referal). Disimpan sementara
  // dan di-bind ke profile saat registerProfile selesai.
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
}


class AuthNotifier extends _AuthBase
    with _AuthInitMx, _AuthSettingsMx, _AuthActionsMx {
  AuthNotifier({AuthService? authService, bool autoInit = true})
    : super(authService, autoInit);
}

final authProvider = NotifierProvider<AuthNotifier, AuthData>(AuthNotifier.new);
