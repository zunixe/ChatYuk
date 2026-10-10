import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_flavor.dart';
import '../../config/strings.dart';
import '../../config/theme.dart';
import '../../core/admin_gate.dart';
import '../../screens/point_history/widgets/topup_sheet.dart';
import '../../services/points_service.dart';
import '../../utils.dart';
import '../../widgets/points_toast.dart';

/// State poin/koin (immutable — yang di-watch widget).
class PointsState {
  final int points;
  final bool enabledRaw;
  final bool enabledConfirmed;
  final int bonusBalance;
  final int earnedBalance;
  final bool yukcoinV2Active;
  final bool ghostMode;
  final int extraPhotoSlots;
  final int photoUnlockOnce;
  final int photoUnlockPerm;
  final int roomCreatePaid;
  final int roomCreatePwPaid;
  final int roomJoinPaid;
  final int roomExtendPaid;
  final int bonusMultiplier;
  final int callAudioCostPerMin;
  final int callVideoCostPerMin;
  final int filterGenderCost;
  final int nearbyCost;
  final Map<String, dynamic> featureFlags;

  const PointsState({
    this.points = 50,
    this.enabledRaw = true,
    this.enabledConfirmed = false,
    this.bonusBalance = 0,
    this.earnedBalance = 0,
    this.yukcoinV2Active = false,
    this.ghostMode = false,
    this.extraPhotoSlots = 0,
    this.photoUnlockOnce = 5,
    this.photoUnlockPerm = 20,
    this.roomCreatePaid = 100,
    this.roomCreatePwPaid = 150,
    this.roomJoinPaid = 5,
    this.roomExtendPaid = 50,
    this.bonusMultiplier = 3,
    this.callAudioCostPerMin = 6,
    this.callVideoCostPerMin = 20,
    this.filterGenderCost = 15,
    this.nearbyCost = 25,
    this.featureFlags = const {},
  });

  @override
  bool operator ==(Object other) =>
      other is PointsState &&
      other.points == points &&
      other.enabledRaw == enabledRaw &&
      other.enabledConfirmed == enabledConfirmed &&
      other.bonusBalance == bonusBalance &&
      other.earnedBalance == earnedBalance &&
      other.yukcoinV2Active == yukcoinV2Active &&
      other.ghostMode == ghostMode &&
      other.extraPhotoSlots == extraPhotoSlots &&
      other.photoUnlockOnce == photoUnlockOnce &&
      other.photoUnlockPerm == photoUnlockPerm &&
      other.roomCreatePaid == roomCreatePaid &&
      other.roomCreatePwPaid == roomCreatePwPaid &&
      other.roomJoinPaid == roomJoinPaid &&
      other.roomExtendPaid == roomExtendPaid &&
      other.bonusMultiplier == bonusMultiplier &&
      other.callAudioCostPerMin == callAudioCostPerMin &&
      other.callVideoCostPerMin == callVideoCostPerMin &&
      other.filterGenderCost == filterGenderCost &&
      other.nearbyCost == nearbyCost &&
      mapEquals(other.featureFlags, featureFlags);

  @override
  int get hashCode => Object.hashAll([
    points,
    enabledRaw,
    enabledConfirmed,
    bonusBalance,
    earnedBalance,
    yukcoinV2Active,
    ghostMode,
    extraPhotoSlots,
    photoUnlockOnce,
    photoUnlockPerm,
    roomCreatePaid,
    roomCreatePwPaid,
    roomJoinPaid,
    roomExtendPaid,
    bonusMultiplier,
    callAudioCostPerMin,
    callVideoCostPerMin,
    filterGenderCost,
    nearbyCost,
    Object.hashAllUnordered(
      featureFlags.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  ]);

  bool get enabled => enabledConfirmed && enabledRaw;
  int get paidBalance => earnedBalance;

  int callCostPerMin(String callType) =>
      callType == 'audio' ? callAudioCostPerMin : callVideoCostPerMin;

  bool featurePublished(String feature) =>
      (featureFlags[feature] is Map) &&
      ((featureFlags[feature] as Map)['published'] == true);
  bool get callBillingPublished => featurePublished('call_billing');
  bool get genderFilterPublished => featurePublished('gender_filter_paid');
  bool get nearbyPaidPublished => featurePublished('nearby_paid');
  bool get playTopupPublished => featurePublished('play_topup');
  bool get topupPathOpen => playTopupPublished || yukcoinV2Active;

  int get costUndoMessage => 10;
  int get costEditMessage => 15;
  int get costExtraPhotoSlot => 60;
  int get costGhostModeDaily => 50;
}

/// Saldo koin + harga fitur + lifecycle online (Riverpod).
/// Migrasi dari ChangeNotifier → Notifier. Global (persist sepanjang sesi).
class PointsNotifier extends Notifier<PointsState> with WidgetsBindingObserver {
  final PointsService _service;

  PointsNotifier({PointsService? service})
    : _service = service ?? PointsService(Supabase.instance.client);

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

  int _bonusBalance = 0;
  int _earnedBalance = 0;
  bool _yukcoinV2Active = false;
  bool _ghostMode = false;
  int _extraPhotoSlots = 0;

  final int costUndoMessage = 10;
  final int costEditMessage = 15;
  final int costExtraPhotoSlot = 60;
  final int costGhostModeDaily = 50;

  int _photoUnlockOnce = 5;
  int _photoUnlockPerm = 20;

  int _roomCreatePaid = 100;
  int _roomCreatePwPaid = 150;
  int _roomJoinPaid = 5;
  int _roomExtendPaid = 50;
  int _bonusMultiplier = 3;

  int _callAudioCostPerMin = 6;
  int _callVideoCostPerMin = 20;
  int _filterGenderCost = 15;
  int _nearbyCost = 25;

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
      earnedBalance: _earnedBalance,
      yukcoinV2Active: _yukcoinV2Active,
      ghostMode: _ghostMode,
      extraPhotoSlots: _extraPhotoSlots,
      photoUnlockOnce: _photoUnlockOnce,
      photoUnlockPerm: _photoUnlockPerm,
      roomCreatePaid: _roomCreatePaid,
      roomCreatePwPaid: _roomCreatePwPaid,
      roomJoinPaid: _roomJoinPaid,
      roomExtendPaid: _roomExtendPaid,
      bonusMultiplier: _bonusMultiplier,
      callAudioCostPerMin: _callAudioCostPerMin,
      callVideoCostPerMin: _callVideoCostPerMin,
      filterGenderCost: _filterGenderCost,
      nearbyCost: _nearbyCost,
      featureFlags: Map.unmodifiable(_featureFlags),
    );
  }

  // ── Getter kompat ──
  int get points => _points;
  bool get enabled => _enabledConfirmed && _enabled;
  bool get enabledConfirmed => _enabledConfirmed;
  int get bonusBalance => _bonusBalance;
  int get earnedBalance => _earnedBalance;
  int get paidBalance => _earnedBalance;
  bool get yukcoinV2Active => _yukcoinV2Active;
  bool get ghostMode => _ghostMode;
  int get extraPhotoSlots => _extraPhotoSlots;
  int get photoUnlockOnce => _photoUnlockOnce;
  int get photoUnlockPerm => _photoUnlockPerm;
  int get roomCreatePaid => _roomCreatePaid;
  int get roomCreatePwPaid => _roomCreatePwPaid;
  int get roomJoinPaid => _roomJoinPaid;
  int get roomExtendPaid => _roomExtendPaid;
  int get bonusMultiplier => _bonusMultiplier;
  int get callAudioCostPerMin => _callAudioCostPerMin;
  int get callVideoCostPerMin => _callVideoCostPerMin;
  int get filterGenderCost => _filterGenderCost;
  int get nearbyCost => _nearbyCost;
  int callCostPerMin(String callType) =>
      callType == 'audio' ? _callAudioCostPerMin : _callVideoCostPerMin;
  bool featurePublished(String feature) =>
      (_featureFlags[feature] is Map) &&
      ((_featureFlags[feature] as Map)['published'] == true);
  bool get callBillingPublished => featurePublished('call_billing');
  bool get genderFilterPublished => featurePublished('gender_filter_paid');
  bool get nearbyPaidPublished => featurePublished('nearby_paid');
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
      _filterGenderCost =
          (p['filter_gender_cost'] as num?)?.toInt() ?? _filterGenderCost;
      _nearbyCost = (p['nearby_cost'] as num?)?.toInt() ?? _nearbyCost;
      _featureFlags = await _service.featureFlags();
      _emit();
    } catch (e) {
      dlog('[POINTS] refreshMeteredPricing error: $e');
    }
  }

  Future<bool> gateFeature(String feature, {String? priceFeature}) async {
    try {
      await _service.gateFeature(feature, priceFeature: priceFeature);
      await refreshWallet();
      return true;
    } catch (e) {
      dlog('[POINTS] gateFeature($feature) error: $e');
      rethrow;
    }
  }

  Future<bool> ensureEnoughForCall(
    BuildContext context,
    String callType,
    bool isId,
  ) async {
    if (!_enabled || !callBillingPublished) return true;
    await refreshWallet();
    final need = callCostPerMin(callType);
    if (_points >= need) return true;
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
              isId ? 'Nanti' : 'Later',
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
    if (AppFlavor.topupEnabled || AdminGate.enabled || topupPathOpen) {
      showTopupSheet(context, s);
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
      _roomJoinPaid = (p['join_paid'] as num?)?.toInt() ?? _roomJoinPaid;
      _roomExtendPaid = (p['extend_paid'] as num?)?.toInt() ?? _roomExtendPaid;
      _bonusMultiplier = (p['multiplier'] as num?)?.toInt() ?? _bonusMultiplier;
      _emit();
    } catch (e) {
      dlog('[POINTS] refreshRoomPricing error: $e');
    }
  }

  bool _photoCostsLoadedFlag = false;
  Future<void> refreshPhotoCosts({bool force = false}) async {
    if (_photoCostsLoadedFlag && !force) return;
    try {
      final c = await _service.photoCosts();
      _photoUnlockOnce = c.$1;
      _photoUnlockPerm = c.$2;
      _photoCostsLoadedFlag = true;
      _emit();
    } catch (e) {
      dlog('[POINTS] refreshPhotoCosts error: $e');
    }
  }

  Future<void> refreshWallet() async {
    try {
      final w = await _service.getWallet();
      _bonusBalance = (w['bonus'] as num?)?.toInt() ?? 0;
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

  Future<Map<String, dynamic>> spendYukcoin(
    String feature,
    int amount, {
    String? ref,
  }) => _service.spendYukcoin(feature, amount, ref: ref);
  Future<Map<String, dynamic>> undoMessage(int messageId) =>
      _service.undoMessage(messageId);
  Future<Map<String, dynamic>> editMessage(int messageId, String newText) =>
      _service.editMessage(messageId, newText);
  Future<Map<String, dynamic>> buyExtraPhotoSlots({int slots = 5}) =>
      _service.buyExtraPhotoSlots(slots: slots);
  Future<Map<String, dynamic>> buyGhostMode({int days = 1}) =>
      _service.buyGhostMode(days: days);

  Future<Map<String, dynamic>> quests(int tz) => _service.quests(tz);
  Future<Map<String, dynamic>> claimWeeklyQuest(String key, int tz) =>
      _service.claimWeeklyQuest(key, tz);
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

  void syncFromProfile(int value) {
    if (_disposed) return;
    if (value != _points) {
      _points = value;
      _emit();
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

  Future<void> showOnboardingIfNeeded(BuildContext context, dynamic s) async {
    await refreshEnabled();
    if (_onboardingShown || !enabled) return;
    if (!context.mounted) return;
    markOnboardingShown();
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
                  _onboardItem('🪙', s.pointsOnboardCoinTitle, highlight: true),
                  _onboardItem('💬', s.pointsOnboardCoinBody),
                  _onboardItem('📞', s.pointsOnboardCallFree),
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
    if (!enabled) return;
    if (_sessionStart != null) {
      _todayOnlineSeconds += DateTime.now()
          .difference(_sessionStart!)
          .inSeconds;
      _sessionStart = DateTime.now();
    }
    _tryClaimOnlineBonus();
  }

  Future<void> _tryClaimOnlineBonus() async {}

  void checkAndShowOnlineToast(BuildContext context, bool isId) {}

  void resetOnlineTrackers() {
    _todayOnlineSeconds = 0;
    _sessionStart = DateTime.now();
  }

  Future<void> claimDailyLogin() async {
    resetOnlineTrackers();
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
    if (!_enabled) return;
    try {
      _points = await _service.refundChatPoint(msgType);
      _emit();
    } catch (e) {
      dlog('[POINTS] refundChatPoint error: $e');
    }
  }

  Future<void> roomReadBonus() async {
    if (!enabled) return;
    try {
      _points = await _service.roomReadBonus();
      _emit();
    } catch (e) {
      dlog('[POINTS] roomReadBonus error: $e');
    }
  }

  Future<bool> oneTimeBonus(String actionKey, int bonus) async {
    if (!enabled) return false;
    try {
      final old = _points;
      _points = await _service.oneTimeBonus(actionKey, bonus);
      _emit();
      return _points > old;
    } catch (e) {
      dlog('[POINTS] oneTimeBonus error: $e');
      return false;
    }
  }

  Future<int> rewardPhotoSlot(int slotIndex) async {
    if (!enabled) return 0;
    try {
      final old = _points;
      _points = await _service.rewardPhotoSlot(slotIndex);
      _emit();
      return _points > old ? _points - old : 0;
    } catch (e) {
      dlog('[POINTS] rewardPhotoSlot error: $e');
      return 0;
    }
  }

  Future<bool> unlockPhoto(String photoId, String mode) async {
    try {
      final res = await _service.unlockPhoto(photoId, mode);
      if (res['points'] != null) setPoints((res['points'] as num).toInt());
      return res['ok'] == true;
    } on PostgrestException catch (e) {
      if (e.message.contains('Not enough points') ||
          e.message.contains('Not enough topup')) {
        throw 'topup';
      }
      dlog('[POINTS] unlockPhoto error: $e');
      rethrow;
    }
  }

  Future<bool> claimRegisterBonus() async {
    if (!enabled) return false;
    try {
      final old = _points;
      _points = await _service.registerBonus();
      _emit();
      return _points > old;
    } catch (e) {
      dlog('[POINTS] registerBonus error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> subscribeCreator(
    String creatorUid, {
    int periods = 1,
  }) async {
    final res = await _service.subscribeCreator(creatorUid, periods: periods);
    await refreshWallet();
    return res;
  }

  Future<Map<String, dynamic>> claimReferralReward() async {
    final res = await _service.claimReferralReward();
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
              isId ? 'Tutup' : 'Close',
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
