import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_flavor.dart';
import '../../config/gifts.dart';
import 'auth_provider.dart';
import 'withdraw_provider.dart';
import '../../config/strings.dart';
import '../../config/theme.dart';
import '../../core/admin_gate.dart';
import '../../core/nav_gate.dart';
import '../../services/mission_progress_service.dart';
import '../../services/points_service.dart';
import 'missions_provider.dart';
import '../../utils.dart';
import 'match_pricing_provider.dart';
import '../../widgets/points_toast.dart';

/// State poin/koin (immutable — yang di-watch widget).
class PointsState {
  final int points;
  final bool enabledRaw;
  final bool enabledConfirmed;
  final int bonusBalance;
  final int topupBalance;
  final int earnedBalance;
  final bool yukcoinV2Active;
  final bool ghostMode;
  final int extraPhotoSlots;
  final int roomCreatePaid;
  final int roomCreatePwPaid;
  final int roomExtendPaid;
  final int bonusMultiplier;
  final int callAudioCostPerMin;
  final int callVideoCostPerMin;
  final Map<String, dynamic> featureFlags;

  const PointsState({
    this.points = 50,
    this.enabledRaw = true,
    this.enabledConfirmed = false,
    this.bonusBalance = 0,
    this.topupBalance = 0,
    this.earnedBalance = 0,
    this.yukcoinV2Active = false,
    this.ghostMode = false,
    this.extraPhotoSlots = 0,
    this.roomCreatePaid = 100,
    this.roomCreatePwPaid = 150,
    this.roomExtendPaid = 50,
    this.bonusMultiplier = 3,
    this.callAudioCostPerMin = 6,
    this.callVideoCostPerMin = 20,
    this.featureFlags = const {},
  });

  @override
  bool operator ==(Object other) =>
      other is PointsState &&
      other.points == points &&
      other.enabledRaw == enabledRaw &&
      other.enabledConfirmed == enabledConfirmed &&
      other.bonusBalance == bonusBalance &&
      other.topupBalance == topupBalance &&
      other.earnedBalance == earnedBalance &&
      other.yukcoinV2Active == yukcoinV2Active &&
      other.ghostMode == ghostMode &&
      other.extraPhotoSlots == extraPhotoSlots &&
      other.roomCreatePaid == roomCreatePaid &&
      other.roomCreatePwPaid == roomCreatePwPaid &&
      other.roomExtendPaid == roomExtendPaid &&
      other.bonusMultiplier == bonusMultiplier &&
      other.callAudioCostPerMin == callAudioCostPerMin &&
      other.callVideoCostPerMin == callVideoCostPerMin &&
      mapEquals(other.featureFlags, featureFlags);

  @override
  int get hashCode => Object.hashAll([
    points,
    enabledRaw,
    enabledConfirmed,
    bonusBalance,
    topupBalance,
    earnedBalance,
    yukcoinV2Active,
    ghostMode,
    extraPhotoSlots,
    roomCreatePaid,
    roomCreatePwPaid,
    roomExtendPaid,
    bonusMultiplier,
    callAudioCostPerMin,
    callVideoCostPerMin,
    Object.hashAllUnordered(
      featureFlags.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  ]);

  bool get enabled => enabledConfirmed && enabledRaw;
  /// Koin "beli" = topup + penghasilan. Bucket `bonus` (gratis) TIDAK
  /// dihitung — server (send_gift/unlock_photo) menolak bonus.
  int get paidBalance => topupBalance + earnedBalance;

  int callCostPerMin(String callType) =>
      callType == 'audio' ? callAudioCostPerMin : callVideoCostPerMin;

  bool featurePublished(String feature) =>
      (featureFlags[feature] is Map) &&
      ((featureFlags[feature] as Map)['published'] == true);
  bool get callBillingPublished => featurePublished('call_billing');
  bool get playTopupPublished => featurePublished('play_topup');
  bool get topupPathOpen => playTopupPublished || yukcoinV2Active;

}

/// Saldo koin + harga fitur + lifecycle online (Riverpod).
/// Migrasi dari ChangeNotifier → Notifier. Global (persist sepanjang sesi).
class PointsNotifier extends Notifier<PointsState> with WidgetsBindingObserver {
  final PointsService _service;
  final MissionProgressService _missionProgress;

  PointsNotifier({PointsService? service, MissionProgressService? missionProgress})
    : _service = service ?? PointsService(Supabase.instance.client),
      _missionProgress = missionProgress ?? MissionProgressService();

  var _disposed = false;
  int _points = 50;
  int _todayOnlineSeconds = 0;
  DateTime? _sessionStart;
  Timer? _onlineTickTimer;
  bool _onboardingShown = false;
  bool _enabled = true;
  bool _enabledConfirmed = false;
  StreamSubscription<bool>? _enabledSub;
  StreamSubscription<int>? _pointsSub;
  StreamSubscription<AuthState>? _authSub;
  Timer? _walletDebounce;

  /// Menit online yang SUDAH dikirim ke misi (dasar hitung delta).
  /// Tanpa ini tiap tick 30 detik mengirim kumulatif → progress dobel.
  int _missionOnlineMinutesSent = 0;

  /// Total koin terakhir yang dikirim ke misi `nyonya_1000`.

  int _bonusBalance = 0;
  int _topupBalance = 0;
  int _earnedBalance = 0;
  bool _yukcoinV2Active = false;
  bool _ghostMode = false;
  int _extraPhotoSlots = 0;



  int _roomCreatePaid = 100;
  int _roomCreatePwPaid = 150;
  int _roomExtendPaid = 50;
  int _bonusMultiplier = 3;

  int _callAudioCostPerMin = 6;
  int _callVideoCostPerMin = 20;

  Map<String, dynamic> _featureFlags = {};

  @override
  PointsState build() {
    ref.onDispose(_disposeAll);
    WidgetsBinding.instance.addObserver(this);
    _sessionStart = DateTime.now();
    _onlineTickTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkOnlineMilestones(),
    );
    subscribeOwnPoints();
    unawaited(refreshMeteredPricing());
    unawaited(checkOnboarding());
    unawaited(refreshEnabled());
    subscribeEnabled();
    try {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(
        (state) {
          if (_disposed) return;
          if (state.event == AuthChangeEvent.initialSession ||
              state.event == AuthChangeEvent.signedIn ||
              state.event == AuthChangeEvent.tokenRefreshed ||
              state.event == AuthChangeEvent.signedOut) {
            subscribeOwnPoints();
          }
          if (state.event == AuthChangeEvent.signedOut) {
            _enabledSub?.cancel();
            _enabledSub = null;
            subscribeEnabled();
          }
        },
        onError: (e) {
          dlog('[POINTS] auth stream error: $e');
        },
      );
    } catch (e) {
      dlog('[POINTS] auth listener error: $e');
    }
    return const PointsState();
  }

  void _emit() {
    if (_disposed) return;
    state = PointsState(
      points: _points,
      enabledRaw: _enabled,
      enabledConfirmed: _enabledConfirmed,
      bonusBalance: _bonusBalance,
      topupBalance: _topupBalance,
      earnedBalance: _earnedBalance,
      yukcoinV2Active: _yukcoinV2Active,
      ghostMode: _ghostMode,
      extraPhotoSlots: _extraPhotoSlots,
      roomCreatePaid: _roomCreatePaid,
      roomCreatePwPaid: _roomCreatePwPaid,
      roomExtendPaid: _roomExtendPaid,
      bonusMultiplier: _bonusMultiplier,
      callAudioCostPerMin: _callAudioCostPerMin,
      callVideoCostPerMin: _callVideoCostPerMin,
      featureFlags: Map.unmodifiable(_featureFlags),
    );
  }

  // ── Getter kompat ──
  int get points => _points;
  bool get enabled => _enabledConfirmed && _enabled;
  bool get enabledConfirmed => _enabledConfirmed;
  int get bonusBalance => _bonusBalance;
  int get topupBalance => _topupBalance;
  int get earnedBalance => _earnedBalance;
  int get paidBalance => _topupBalance + _earnedBalance;
  bool get yukcoinV2Active => _yukcoinV2Active;
  bool get ghostMode => _ghostMode;
  int get extraPhotoSlots => _extraPhotoSlots;
  int get roomCreatePaid => _roomCreatePaid;
  int get roomCreatePwPaid => _roomCreatePwPaid;
  int get roomExtendPaid => _roomExtendPaid;
  int get bonusMultiplier => _bonusMultiplier;
  int get callAudioCostPerMin => _callAudioCostPerMin;
  int get callVideoCostPerMin => _callVideoCostPerMin;
  int callCostPerMin(String callType) =>
      callType == 'audio' ? _callAudioCostPerMin : _callVideoCostPerMin;
  bool featurePublished(String feature) =>
      (_featureFlags[feature] is Map) &&
      ((_featureFlags[feature] as Map)['published'] == true);
  bool get callBillingPublished => featurePublished('call_billing');
  bool get playTopupPublished => featurePublished('play_topup');
  bool get topupPathOpen => playTopupPublished || yukcoinV2Active;
  @visibleForTesting
  int get onlineSecondsForTest => _todayOnlineSeconds;
  @visibleForTesting
  void setOnlineSecondsForTest(int v) => _todayOnlineSeconds = v;
  @visibleForTesting
  Future<void> debugClaimOnlineBonus() => _tryClaimOnlineBonus();

  Future<void> refreshMeteredPricing() async {
    try {
      final p = await _service.meteredPricing();
      _callAudioCostPerMin =
          (p['call_audio_cost_per_min'] as num?)?.toInt() ??
          _callAudioCostPerMin;
      _callVideoCostPerMin =
          (p['call_video_cost_per_min'] as num?)?.toInt() ??
          _callVideoCostPerMin;
      _featureFlags = await _service.featureFlags();
      _emit();
    } catch (e) {
      dlog('[POINTS] refreshMeteredPricing error: $e');
    }
  }


  Future<bool> ensureEnoughForCall(
    BuildContext context,
    String callType,
    bool isId,
  ) async {
    if (!_enabled || !callBillingPublished) return true;
    // FEMALE CALLER = GRATIS (server: 30 menit/hari, ditegakkan di
    // call_billing_tick). Jangan blokir di client — female dengan 0 koin
    // adalah kondisi normal (koinnya datang dari lawan bicara), dan dulu
    // dialog "YukCoin tidak cukup" membatalkan panggilannya sama sekali.
    final myGender = ref.read(authProvider.notifier).profile?.gender;
    if (myGender == 'female') return true;
    await refreshWallet();
    final need = callCostPerMin(callType);
    // Server (charge_metered/call_billing_tick sejak 2026-11-01) HANYA
    // menerima koin beli/penghasilan (topup+earned). Koin `bonus` ditolak
    // — cek pakai paid, bukan total, agar dialog top-up muncul sebelum
    // call diputus di tengah.
    if (_topupBalance + _earnedBalance >= need) return true;
    if (!context.mounted) return false;
    final s = S(isId: isId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(
          s.callNeedCoinTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          s.callNeedCoinBody(need),
          style: AppText.bodySmall.copyWith(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              s.btnLater,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openTopupOrSoon(context, s);
            },
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: Text(s.yukcoinTopup),
          ),
        ],
      ),
    );
    return false;
  }

  void _openTopupOrSoon(BuildContext context, S s) {
    final show = NavGate.topupSheet;
    if ((AppFlavor.topupEnabled || AdminGate.enabled || topupPathOpen) &&
        show != null) {
      show(context, s);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.yukcoinTopupSoon)));
    }
  }

  Future<int> claimWelcomeBonus({
    required String installId,
    required String kind,
  }) async {
    try {
      final res = await _service.claimWelcomeBonus(
        installId: installId,
        kind: kind,
      );
      await refreshWallet();
      return (res['coins'] as num?)?.toInt() ?? 0;
    } catch (e) {
      dlog('[POINTS] claimWelcomeBonus($kind) error: $e');
      return 0;
    }
  }

  Future<void> refreshRoomPricing() async {
    try {
      final p = await _service.roomPricing();
      _roomCreatePaid = (p['create_paid'] as num?)?.toInt() ?? _roomCreatePaid;
      _roomCreatePwPaid =
          (p['create_pw_paid'] as num?)?.toInt() ?? _roomCreatePwPaid;
      // join_paid diabaikan: join room GRATIS di server sejak 2026-08-27.
      _roomExtendPaid = (p['extend_paid'] as num?)?.toInt() ?? _roomExtendPaid;
      _bonusMultiplier = (p['multiplier'] as num?)?.toInt() ?? _bonusMultiplier;
      _emit();
    } catch (e) {
      dlog('[POINTS] refreshRoomPricing error: $e');
    }
  }


  Future<void> refreshWallet() async {
    try {
      final w = await _service.getWallet();
      _bonusBalance = (w['bonus'] as num?)?.toInt() ?? 0;
      _topupBalance = (w['topup'] as num?)?.toInt() ?? 0;
      _earnedBalance = (w['earned'] as num?)?.toInt() ?? 0;
      _points = (w['total'] as num?)?.toInt() ?? _points;
      _emit();
    } catch (e) {
      dlog('[POINTS] getWallet error: $e');
    }
    unawaited(refreshYukcoinV2());
  }

  Future<void> refreshYukcoinV2() async {
    try {
      final st = await _service.yukcoinV2Status();
      _yukcoinV2Active = st['active'] == true;
      _ghostMode = st['ghost'] == true;
      _extraPhotoSlots = (st['extra_slots'] as num?)?.toInt() ?? 0;
      _emit();
    } catch (e) {
      dlog('[POINTS] refreshYukcoinV2 error: $e');
    }
  }

  Future<Map<String, dynamic>> undoMessage(int messageId) =>
      _service.undoMessage(messageId);
  Future<Map<String, dynamic>> buyExtraPhotoSlots({int slots = 5}) =>
      _service.buyExtraPhotoSlots(slots: slots);

  Future<Map<String, dynamic>> leaderboard(
    String scope, {
    int limit = 50,
    int offset = 0,
  }) => _service.leaderboard(scope, limit: limit, offset: offset);
  Future<Map<String, dynamic>> activityLeaderboard(String scope) =>
      _service.activityLeaderboard(scope);
  Future<List<Map<String, dynamic>>> pointHistory({
    int limit = 100,
    int offset = 0,
  }) => _service.pointHistory(limit: limit, offset: offset);

  void subscribeOwnPoints() {
    try {
      _pointsSub?.cancel();
      _pointsSub = _service.watchOwnPoints().listen(
        (value) {
          if (_disposed) return;
          final changed = value != _points;
          _points = value;
          _emit();
          if (changed) {
            _walletDebounce?.cancel();
            _walletDebounce = Timer(const Duration(milliseconds: 800), () {
              if (_disposed) return;
              refreshWallet();
            });
          }
        },
        onError: (e) {
          dlog('[POINTS] points stream error: $e');
        },
      );
      refreshWallet();
    } catch (e) {
      dlog('[POINTS] watchOwnPoints error: $e');
    }
  }



  void subscribeEnabled() {
    try {
      _enabledSub ??= _service.watchEnabled().listen(
        (value) {
          if (_disposed) return;
          _enabledConfirmed = true;
          _enabled = value;
          _emit();
        },
        onError: (e) {
          dlog('[POINTS] enabled stream error: $e');
        },
      );
    } catch (e) {
      dlog('[POINTS] watchEnabled error: $e');
    }
  }

  Future<void> refreshEnabled() async {
    try {
      _enabled = await _service.fetchEnabled();
      _enabledConfirmed = true;
      _emit();
    } catch (e) {
      dlog('[POINTS] fetchEnabled error: $e');
    }
  }

  void setPoints(int value) {
    _points = value;
    _emit();
  }

  static const _onboardingKey = 'points_onboarding_shown';

  Future<void> checkOnboarding() async {
    if (_onboardingShown) return;
    final prefs = await SharedPreferences.getInstance();
    _onboardingShown = prefs.getBool(_onboardingKey) == true;
  }

  Future<void> markOnboardingShown() async {
    _onboardingShown = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
  }

  /// Minimum withdraw dari server (get_withdraw_config). Fallback ke nilai
  /// default config bila provider belum dimuat — onboarding hanya tampilan.
  int _withdrawMinCoins() {
    try {
      return ref.read(withdrawProvider).config.minCoins;
    } catch (_) {
      return 2000;
    }
  }

  Future<void> showOnboardingIfNeeded(
    BuildContext context,
    dynamic s, {
    String? gender,
  }) async {
    await refreshEnabled();
    if (_onboardingShown || !enabled) return;
    if (!context.mounted) return;
    markOnboardingShown();
    final isFemale = gender == 'female';
    final callAudio = _callAudioCostPerMin;
    final callVideo = _callVideoCostPerMin;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              decoration: BoxDecoration(
                gradient: AppTheme.headerGradient,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Row(
                children: [
                  Text('🪙', style: TextStyle(fontSize: AppGlyph.lg)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.pointsOnboardTitle,
                          style: AppText.title.copyWith(color: Colors.white),
                        ),
                        Text(
                          s.pointsOnboardSub,
                          style: AppText.caption.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Kopi per gender: male = apa yang DIBAYAR, female = cara
                  // MENDAPAT. Aturan ekonominya memang asimetris (male bayar,
                  // female menerima), jadi satu teks untuk keduanya menyesatkan.
                  if (isFemale) ...[
                    _onboardItem('💰', s.pointsOnboardFemaleSub,
                        highlight: true),
                    _onboardItem('', s.pointsOnboardFemaleCall),
                    _onboardItem('', s.pointsOnboardFemaleGift),
                    _onboardItem('', s.pointsOnboardFemaleMatch),
                    _onboardItem(
                        '',
                        s.pointsOnboardFemaleWithdraw(
                            _withdrawMinCoins())),
                  ] else ...[
                    _onboardItem('🪙', s.pointsOnboardMaleSub, highlight: true),
                    _onboardItem('', s.pointsOnboardMaleCall(callAudio, callVideo)),
                    _onboardItem('', s.pointsOnboardMaleMatch(
                        (ref.read(matchPricingProvider).value ??
                                const MatchPricing())
                            .searchCoins)),
                    _onboardItem(
                        '',
                        s.pointsOnboardMaleGift(
                            kGiftCatalog.first.coins,
                            kGiftCatalog.last.coins)),
                    _onboardItem('', s.pointsOnboardMaleFree),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text('🎉', style: TextStyle(fontSize: AppGlyph.sm)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.pointsOnboardStart,
                          style: AppText.bodySmall.copyWith(
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2ECC71),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text(s.pointsOnboardOk, style: AppText.button),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _onboardItem(String emoji, String text, {bool highlight = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFF2ECC71).withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlight
              ? const Color(0xFF2ECC71).withValues(alpha: 0.5)
              : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Text(emoji, style: TextStyle(fontSize: AppGlyph.md)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppText.body.copyWith(
                color: highlight ? Colors.white : Colors.white70,
                fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      refreshEnabled();
      _sessionStart = DateTime.now();
      _onlineTickTimer?.cancel();
      _onlineTickTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _checkOnlineMilestones(),
      );
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_sessionStart != null) {
        _todayOnlineSeconds += DateTime.now()
            .difference(_sessionStart!)
            .inSeconds;
        _sessionStart = null;
      }
      _onlineTickTimer?.cancel();
      _checkOnlineMilestones();
    }
  }

  void _checkOnlineMilestones() {
    if (_sessionStart != null) {
      _todayOnlineSeconds += DateTime.now()
          .difference(_sessionStart!)
          .inSeconds;
      _sessionStart = DateTime.now();
    }
    _trackOnlineMissions();
    _tryClaimOnlineBonus();
  }

  /// Kirim menit online ke misi — HANYA DELTA yang belum pernah dikirim.
  /// Dulu mengirim nilai kumulatif tiap 30 detik → progress bisa 3× lipat.
  void _trackOnlineMissions() {
    final totalMinutes = _todayOnlineSeconds ~/ 60;
    final delta = totalMinutes - _missionOnlineMinutesSent;
    if (delta <= 0) return;
    _missionOnlineMinutesSent = totalMinutes;

    unawaited(_missionProgress.updateProgress(
      'daily_online_minutes',
      increment: delta,
    ));
    unawaited(_missionProgress.updateProgress(
      'daily_online_duration',
      increment: delta,
    ));

    // Misi jam khusus: 19:00–23:00 & 01:00–05:00 (waktu device).
    final h = DateTime.now().hour;
    if (h >= 19 && h < 23) {
      unawaited(_missionProgress.updateProgress(
        'evening_online_call',
        increment: delta,
      ));
    } else if (h >= 1 && h < 5) {
      unawaited(_missionProgress.updateProgress(
        'night_owl_online_call',
        increment: delta,
      ));
    }
  }

  Future<void> _tryClaimOnlineBonus() async {}

  void checkAndShowOnlineToast(BuildContext context, bool isId) {}

  void resetOnlineTrackers() {
    _todayOnlineSeconds = 0;
    _missionOnlineMinutesSent = 0;
    _sessionStart = DateTime.now();
  }

  /// Klaim bonus login harian (halaman Bonus, male). Server idempotent:
  /// klaim ulang hari sama → bonus 0. Return {streak, bonus} untuk toast.
  Future<({int streak, int bonus})> claimDailyLogin() async {
    resetOnlineTrackers();
    if (!enabled) return (streak: 0, bonus: 0);
    try {
      final res = await _service.dailyLoginBonus();
      final bonus = (res['bonus'] as num?)?.toInt() ?? 0;
      final total = (res['total'] as num?)?.toInt() ?? 0;
      if (total > 0) {
        _points = total;
        _emit();
      }
      // Grid streak dibaca missionsProvider — segarkan setelah klaim.
      unawaited(ref.read(missionsProvider.notifier).refresh());
      return (
        streak: (res['streak'] as num?)?.toInt() ?? 0,
        bonus: bonus,
      );
    } catch (e) {
      dlog('[POINTS] claimDailyLogin error: $e');
      return (streak: 0, bonus: 0);
    }
  }

  /// Passthrough untuk tracking mission progress dari widgets/screen (Fase B boundary).
  ///
  /// Dibungkus try/catch: tracking misi adalah efek samping NON-KRITIS. Kalau
  /// Supabase belum siap (test / cold start), jangan sampai membuat aksi
  /// utama (kirim pesan, like, follow) ikut gagal.
  void trackMission(String missionKey, {int increment = 1}) {
    try {
      unawaited(_missionProgress.updateProgress(missionKey, increment: increment));
    } catch (e) {
      dlog('[MISSIONS] trackMission($missionKey) dilewati: $e');
    }
  }

  void checkAndShowStreakToast(BuildContext context, bool isId) {}

  Future<bool> newChatBonus(String otherUid) async {
    if (!enabled) return false;
    try {
      final old = _points;
      _points = await _service.newChatBonus(otherUid);
      _emit();
      return _points > old;
    } catch (e) {
      dlog('[POINTS] newChatBonus error: $e');
      return false;
    }
  }

  Future<int> deductBeforeSend(String msgType) async {
    // 2026-10-31: pesan teks GRATIS di server (deduct_chat_point no-op).
    // Jangan tembak RPC per pesan — hemat radio/baterai di chat aktif.
    if (msgType == 'text') return _points;
    if (!_enabled) return _points;
    try {
      final remaining = await _service.deductChatPoint(msgType);
      _points = remaining;
      _emit();
      return remaining;
    } on PostgrestException catch (e) {
      if (e.message.contains('Not enough points')) return -1;
      dlog('[POINTS] deduct error: $e');
      return -2;
    } catch (e) {
      dlog('[POINTS] deduct error: $e');
      return -2;
    }
  }

  Future<void> refundChatPoint(String msgType) async {
    // Teks gratis → tidak ada yang direfund (refund_chat_point juga no-op).
    if (msgType == 'text') return;
    if (!_enabled) return;
    try {
      _points = await _service.refundChatPoint(msgType);
      _emit();
    } catch (e) {
      dlog('[POINTS] refundChatPoint error: $e');
    }
  }






  Future<Map<String, dynamic>> subscribeCreator(
    String creatorUid, {
    int periods = 1,
    int? expectedPrice,
  }) async {
    final res = await _service.subscribeCreator(creatorUid,
        periods: periods, expectedPrice: expectedPrice);
    await refreshWallet();
    return res;
  }


  void showPointsToast(
    BuildContext context,
    String message, {
    bool isError = false,
  }) {
    if (!enabled) return;
    try {
      final overlay = Overlay.of(context);
      late OverlayEntry entry;
      var removed = false;
      void removeOnce() {
        if (removed) return;
        removed = true;
        try {
          entry.remove();
        } catch (e) {
          dlog('[PointsProvider] showPointsToast ignored: $e');
        }
      }

      entry = OverlayEntry(
        builder: (_) => PointsToast(
          message: message,
          isError: isError,
          onDismiss: removeOnce,
        ),
      );
      overlay.insert(entry);
      Future.delayed(const Duration(milliseconds: 2000), removeOnce);
    } catch (e) {
      dlog('[PointsProvider] showPointsToast ignored: $e');
    }
  }

  void showOutOfPointsDialog(BuildContext context, bool isId) {
    if (!enabled) return;
    final s = S(isId: isId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(
          s.outOfPointsTitle,
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.pointsOutOfCoinBody,
                style: AppText.bodySmall.copyWith(color: Colors.white70),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _openTopupOrSoon(context, s);
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  label: Text(s.yukcoinTopup),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              s.btnClose,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  void _disposeAll() {
    _disposed = true;
    _enabledSub?.cancel();
    _pointsSub?.cancel();
    _authSub?.cancel();
    _walletDebounce?.cancel();
    _onlineTickTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Passthrough paket topup (Fase B boundary): screen topup dilarang import
  /// services/. Delegasi ke `_service.listTopupPackages()`.
  Future<List<Map<String, dynamic>>> listTopupPackages() =>
      _service.listTopupPackages();
}

final pointsProvider = NotifierProvider<PointsNotifier, PointsState>(
  PointsNotifier.new,
);
