import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/points_service.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../utils.dart';

class PointsProvider extends ChangeNotifier with WidgetsBindingObserver {
  final PointsService _service;
  int _points = 50;
  bool _disposed = false;
  // Tracking durasi online dipertahankan untuk metrik internal sesi.
  // Bonus online DIHAPUS (overhaul coin) — tak ada klaim milestone lagi.
  int _todayOnlineSeconds = 0;
  DateTime? _sessionStart;
  Timer? _onlineTickTimer;
  bool _onboardingShown = false;
  // Default TRUE TAPI _enabledConfirmed=false: UI fitur koin (gift dsb.)
  // baru tampil setelah flag server terkonfirmasi — mencegah kilatan
  // gift muncul-lalu-hilang di frame awal saat admin mematikan koin.
  bool _enabled = true;
  bool _enabledConfirmed = false;
  StreamSubscription<bool>? _enabledSub;
  StreamSubscription<int>? _pointsSub;
  StreamSubscription<AuthState>? _authSub;
  Timer? _walletDebounce;

  int get points => _points;

  /// Sistem koin aktif untuk user ini — murni mengikuti nilai server
  /// (app_settings.points_enabled). Saat dimatikan, koin disembunyikan
  /// untuk SEMUA user termasuk admin build. Dulu ada over-ride admin/dev
  /// yang membuat koin selalu tampil di build admin padahal dimatikan.
  bool get enabled => _enabledConfirmed && _enabled;

  /// Flag server sudah terkonfirmasi (fetch/subscribe balik) — dipakai
  /// UI untuk memutuskan menampilkan fitur koin tanpa kilatan awal.
  bool get enabledConfirmed => _enabledConfirmed;

  // Wallet bucket (Fase 1). _points tetap = total (kompat UI lama).
  int _bonusBalance = 0;
  int _earnedBalance = 0;
  int get bonusBalance => _bonusBalance;
  int get earnedBalance => _earnedBalance;

  /// Saldo "pro" (earned) — koin yang bisa dipakai untuk fitur berbayar
  /// (kirim koin, gift, room private, subscribe, buka foto). Bucket topup
  /// dihapus bersama fitur finansial.
  int get paidBalance => _earnedBalance;

  // ── YukCoin v2 ──────────────────────────────────────────────
  // Satu saldo terpadu untuk UI (total = bonus + earned). Fitur v2 aktif
  // hanya bila server bilang true untuk user ini (flag global / admin).
  bool _yukcoinV2Active = false;
  bool get yukcoinV2Active => _yukcoinV2Active;

  bool _ghostMode = false;
  bool get ghostMode => _ghostMode;

  int _extraPhotoSlots = 0;
  int get extraPhotoSlots => _extraPhotoSlots;

  // Biaya fitur YukCoin v2 (default sesuai migration; sumber kebenaran
  // tetap server — nilai ini hanya untuk tampilan harga di UI).
  final int costUndoMessage = 10;
  final int costEditMessage = 15;
  final int costExtraPhotoSlot = 60;
  final int costGhostModeDaily = 50;

  // Biaya buka foto terkunci (dari app_settings; default sesuai server).
  int _photoUnlockOnce = 5;
  int _photoUnlockPerm = 20;
  int get photoUnlockOnce => _photoUnlockOnce;
  int get photoUnlockPerm => _photoUnlockPerm;

  // Harga room private (dual pricing, dari server).
  int _roomCreatePaid = 100;
  int _roomCreatePwPaid = 150;
  int _roomJoinPaid = 5;
  int _roomExtendPaid = 50;
  int _bonusMultiplier = 3;
  int get roomCreatePaid => _roomCreatePaid;
  int get roomCreatePwPaid => _roomCreatePwPaid;
  int get roomJoinPaid => _roomJoinPaid;
  int get roomExtendPaid => _roomExtendPaid;
  int get bonusMultiplier => _bonusMultiplier;

  // ── Harga fitur berbayar (call per menit, filter, nearby) ──
  int _callAudioCostPerMin = 6;
  int _callVideoCostPerMin = 20;
  int _filterGenderCost = 15;
  int _nearbyCost = 25;
  int get callAudioCostPerMin => _callAudioCostPerMin;
  int get callVideoCostPerMin => _callVideoCostPerMin;
  int get filterGenderCost => _filterGenderCost;
  int get nearbyCost => _nearbyCost;

  /// Harga per menit sesuai tipe call.
  int callCostPerMin(String callType) =>
      callType == 'audio' ? _callAudioCostPerMin : _callVideoCostPerMin;

  /// Feature flags yang sudah "published" (gate UI). {} bila belum dimuat.
  Map<String, dynamic> _featureFlags = {};
  bool featurePublished(String feature) =>
      (_featureFlags[feature] is Map) &&
      ((_featureFlags[feature] as Map)['published'] == true);
  bool get callBillingPublished => featurePublished('call_billing');
  bool get genderFilterPublished => featurePublished('gender_filter_paid');
  bool get nearbyPaidPublished => featurePublished('nearby_paid');
  bool get playTopupPublished => featurePublished('play_topup');

  /// Ambil harga fitur + feature flags dari server.
  Future<void> refreshMeteredPricing() async {
    try {
      final p = await _service.meteredPricing();
      _callAudioCostPerMin =
          (p['call_audio_cost_per_min'] as num?)?.toInt() ?? _callAudioCostPerMin;
      _callVideoCostPerMin =
          (p['call_video_cost_per_min'] as num?)?.toInt() ?? _callVideoCostPerMin;
      _filterGenderCost =
          (p['filter_gender_cost'] as num?)?.toInt() ?? _filterGenderCost;
      _nearbyCost = (p['nearby_cost'] as num?)?.toInt() ?? _nearbyCost;
      _featureFlags = await _service.featureFlags();
      if (!_disposed) notifyListeners();
    } catch (e) {
      dlog('[POINTS] refreshMeteredPricing error: $e');
    }
  }

  /// Potong akses harian (filter gender / nearby). Return true bila boleh
  /// lanjut. Melempar 'YukCoin tidak cukup' bila saldo kurang.
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

  /// Gate sebelum nelp: butuh saldo >= tarif 1 menit. Bila kurang → tampilkan
  /// dialog EDUKASI (coin dipakai untuk nelp) + tombol topup, return false.
  /// Bila cukup → true (boleh mulai call).
  Future<bool> ensureEnoughForCall(
    BuildContext context,
    String callType,
    bool isId,
  ) async {
    await refreshWallet();
    final need = callCostPerMin(callType);
    if (_points >= need) return true;
    if (!context.mounted) return false;
    final s = S(isId: isId);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(s.callNeedCoinTitle,
            style: const TextStyle(color: Colors.white)),
        content: Text(
          s.callNeedCoinBody(need),
          style: AppText.bodySmall.copyWith(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(isId ? 'Nanti' : 'Later',
                style: const TextStyle(color: Colors.white70)),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.yukcoinTopupSoon)),
              );
            },
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: Text(s.yukcoinTopup),
          ),
        ],
      ),
    );
    return false;
  }

  /// Klaim welcome bonus (anon/register) via server. Return jumlah coin
  /// yang benar-benar diberikan (0 bila tidak / sudah diklaim).
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

  /// Ambil harga room dari server (dipanggil saat buka lobby).
  Future<void> refreshRoomPricing() async {
    try {
      final p = await _service.roomPricing();
      _roomCreatePaid = (p['create_paid'] as num?)?.toInt() ?? _roomCreatePaid;
      _roomCreatePwPaid =
          (p['create_pw_paid'] as num?)?.toInt() ?? _roomCreatePwPaid;
      _roomJoinPaid = (p['join_paid'] as num?)?.toInt() ?? _roomJoinPaid;
      _roomExtendPaid = (p['extend_paid'] as num?)?.toInt() ?? _roomExtendPaid;
      _bonusMultiplier = (p['multiplier'] as num?)?.toInt() ?? _bonusMultiplier;
      if (!_disposed) notifyListeners();
    } catch (e) {
      dlog('[POINTS] refreshRoomPricing error: $e');
    }
  }

  /// Ambil nominal biaya foto dari server (dipanggil saat buka profil orang).
  Future<void> refreshPhotoCosts() async {
    try {
      final c = await _service.photoCosts();
      _photoUnlockOnce = c.$1;
      _photoUnlockPerm = c.$2;
      if (!_disposed) notifyListeners();
    } catch (e) {
      dlog('[POINTS] refreshPhotoCosts error: $e');
    }
  }

  /// Ambil saldo wallet bucket dari server (RPC get_wallet).
  Future<void> refreshWallet() async {
    try {
      final w = await _service.getWallet();
      _bonusBalance = (w['bonus'] as num?)?.toInt() ?? 0;
      _earnedBalance = (w['earned'] as num?)?.toInt() ?? 0;
      _points = (w['total'] as num?)?.toInt() ?? _points;
      if (!_disposed) notifyListeners();
    } catch (e) {
      dlog('[POINTS] getWallet error: $e');
    }
    // Status fitur YukCoin v2 (flag server / admin) + ghost mode.
    unawaited(refreshYukcoinV2());
  }

  /// Ambil status & biaya fitur YukCoin v2 dari server.
  Future<void> refreshYukcoinV2() async {
    try {
      final st = await _service.yukcoinV2Status();
      _yukcoinV2Active = st['active'] == true;
      _ghostMode = st['ghost'] == true;
      _extraPhotoSlots = (st['extra_slots'] as num?)?.toInt() ?? 0;
      if (!_disposed) notifyListeners();
    } catch (e) {
      dlog('[POINTS] refreshYukcoinV2 error: $e');
    }
  }

  // ── Passthrough YukCoin v2 ──
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

  // ── Passthrough (Fase 9b) ──
  Future<Map<String, dynamic>> quests(int tz) => _service.quests(tz);
  Future<Map<String, dynamic>> claimWeeklyQuest(String key, int tz) =>
      _service.claimWeeklyQuest(key, tz);
  Future<Map<String, dynamic>> leaderboard(String scope) =>
      _service.leaderboard(scope);
  Future<List<Map<String, dynamic>>> pointHistory({int limit = 100}) =>
      _service.pointHistory(limit: limit);

  PointsProvider({PointsService? service})
    : _service = service ?? PointsService(Supabase.instance.client) {
    // Daftarkan observer + mulai sesi online SEKARANG. Tanpa ini,
    // didChangeAppLifecycleState tidak pernah terpanggil (observer tak
    // terdaftar) sehingga bonus online tidak pernah jalan, dan sesi
    // pertama (cold start) tidak terhitung.
    WidgetsBinding.instance.addObserver(this);
    _sessionStart = DateTime.now();
    _onlineTickTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkOnlineMilestones(),
    );
    // Sinkron saldo koin via realtime profiles — koin masuk (transfer) &
    // keluar (belanja) langsung tampil tanpa reload.
    subscribeOwnPoints();
    // Harga fitur berbayar (call/filter/nearby) + feature flags untuk UI.
    unawaited(refreshMeteredPricing());
    // Saat user berganti (login/logout), stream poin harus di-resubscribe
    // supaya menunjuk ke row profiles yang benar.
    try {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((
        state,
      ) {
        if (_disposed) return;
        if (state.event == AuthChangeEvent.initialSession ||
            state.event == AuthChangeEvent.signedIn ||
            state.event == AuthChangeEvent.tokenRefreshed ||
            state.event == AuthChangeEvent.signedOut) {
          subscribeOwnPoints();
        }
        // signOut men-teardown semua channel realtime (removeAllChannels) —
        // watchEnabled harus di-resubscribe ulang, `??=` saja tidak cukup.
        if (state.event == AuthChangeEvent.signedOut) {
          _enabledSub?.cancel();
          _enabledSub = null;
          subscribeEnabled();
        }
      }, onError: (e) {
        dlog('[POINTS] auth stream error: $e');
      });
    } catch (e) {
      dlog('[POINTS] auth listener error: $e');
    }
  }

  /// Realtime saldo koin sendiri. Di-resubscribe saat user berganti (login/
  /// logout) supaya stream menunjuk ke row yang benar.
  void subscribeOwnPoints() {
    try {
      _pointsSub?.cancel();
      _pointsSub = _service.watchOwnPoints().listen((value) {
        if (_disposed) return;
        // profiles.points = cache total ledger. Saat berubah, tarik rincian
        // bucket dari server supaya bonus/topup/earned ikut ter-update.
        // Debounce: bonus online/chunk pesan bisa memicu banyak event
        // beruntun — cukup 1 RPC get_wallet untuk burst tersebut.
        final changed = value != _points;
        _points = value;
        notifyListeners();
        if (changed) {
          _walletDebounce?.cancel();
          _walletDebounce = Timer(const Duration(milliseconds: 800), () {
            if (_disposed) return;
            refreshWallet();
          });
        }
      }, onError: (e) {
        dlog('[POINTS] points stream error: $e');
      });
      // Ambil rincian awal saat subscribe
      refreshWallet();
    } catch (e) {
      dlog('[POINTS] watchOwnPoints error: $e');
    }
  }

  /// Saldo koin dari profil saat ini (dipakai sebagai nilai awal sebelum
  /// realtime event pertama tiba).
  void syncFromProfile(int value) {
    if (_disposed) return;
    if (value != _points) {
      _points = value;
      notifyListeners();
    }
  }

  void subscribeEnabled() {
    try {
      _enabledSub ??= _service.watchEnabled().listen((value) {
        if (_disposed) return;
        _enabledConfirmed = true;
        _enabled = value;
        notifyListeners();
      }, onError: (e) {
        dlog('[POINTS] enabled stream error: $e');
      });
    } catch (e) {
      dlog('[POINTS] watchEnabled error: $e');
    }
  }

  Future<void> refreshEnabled() async {
    try {
      _enabled = await _service.fetchEnabled();
      _enabledConfirmed = true;
      if (!_disposed) notifyListeners();
    } catch (e) {
      dlog('[POINTS] fetchEnabled error: $e');
    }
  }

  void setPoints(int value) {
    _points = value;
    if (!_disposed) notifyListeners();
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
    // Tunggu fetch flag selesai dulu supaya popup tidak muncul saat disabled.
    // Pakai `enabled` (terkonfirmasi) bukan mentah `_enabled`: kalau fetch
    // gagal, default mentah true akan membocorkan popup padahal server OFF.
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
            // Header gradient elegan.
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
                  // Overhaul coin: tidak ada poin gratis — coin dari topup.
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
      // Refresh flag setiap app kembali aktif, supaya toggle admin
      // langsung berefek tanpa harus restart app
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
    // Pakai `enabled` terkonfirmasi: default mentah true sebelum fetch
    // pertama akan mengklaim bonus + antre toast padahal server OFF.
    if (!enabled) return;
    if (_sessionStart != null) {
      _todayOnlineSeconds += DateTime.now()
          .difference(_sessionStart!)
          .inSeconds;
      _sessionStart = DateTime.now();
    }
    _tryClaimOnlineBonus();
  }

  Future<void> _tryClaimOnlineBonus() async {
    // Faucet dihapus — tidak ada bonus online. (lihat 20261001010000)
  }

  void checkAndShowOnlineToast(BuildContext context, bool isId) {
    // Bonus online DIHAPUS — tidak ada toast. (lihat 20261001010000)
  }

  /// Reset tracker durasi online (dipakai saat daily-login / ganti sesi).
  void resetOnlineTrackers() {
    _todayOnlineSeconds = 0;
    _sessionStart = DateTime.now();
  }

  /// Detik online hari ini (metrik internal, tanpa bonus).
  @visibleForTesting
  int get onlineSecondsForTest => _todayOnlineSeconds;

  /// Hook test: set detik online (kompat lama; tanpa klaim bonus).
  @visibleForTesting
  void setOnlineSecondsForTest(int v) => _todayOnlineSeconds = v;

  @visibleForTesting
  Future<void> debugClaimOnlineBonus() => _tryClaimOnlineBonus();

  Future<void> claimDailyLogin() async {
    // Faucet daily-login DIHAPUS (overhaul coin: tidak ada poin gratis).
    resetOnlineTrackers();
  }

  /// Toast streak DIHAPUS — tidak ada bonus streak lagi.
  void checkAndShowStreakToast(BuildContext context, bool isId) {
    // Tidak ada bonus streak.
  }

  /// Bonus chat orang baru (harian ber-limit, dikelola server).
  Future<bool> newChatBonus(String otherUid) async {
    if (!enabled) return false;
    try {
      final old = _points;
      _points = await _service.newChatBonus(otherUid);
      if (!_disposed) notifyListeners();
      return _points > old;
    } catch (e) {
      dlog('[POINTS] newChatBonus error: $e');
      return false;
    }
  }

  /// Potong poin sebelum kirim pesan. Return:
  ///   >= 0  saldo baru (sukses)
  ///   -1    poin tidak cukup
  ///   -2    error tak dikenal (RPC/network) — JANGAN kirim pesan
  Future<int> deductBeforeSend(String msgType) async {
    // SENGAJA pakai mentah `_enabled` (default true): sebelum flag server
    // terkonfirmasi, kirim tetap dicharge agar tidak ada jendela gratis.
    // Server sendiri mengembalikan saldo tanpa potong saat OFF, jadi aman.
    if (!_enabled) return _points;
    try {
      final remaining = await _service.deductChatPoint(msgType);
      _points = remaining;
      if (!_disposed) notifyListeners();
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

  /// Refund biaya chat saat kirim gagal (upload/blocked/network) — mencegah
  /// koin hilang percuma. Fire-and-forget; kegagalan refund tidak fatal.
  Future<void> refundChatPoint(String msgType) async {
    if (!_enabled) return;
    try {
      _points = await _service.refundChatPoint(msgType);
      if (!_disposed) notifyListeners();
    } catch (e) {
      dlog('[POINTS] refundChatPoint error: $e');
    }
  }

  Future<void> roomReadBonus() async {
    if (!enabled) return;
    try {
      _points = await _service.roomReadBonus();
      if (!_disposed) notifyListeners();
    } catch (e) {
      dlog('[POINTS] roomReadBonus error: $e');
    }
  }

  Future<bool> oneTimeBonus(String actionKey, int bonus) async {
    if (!enabled) return false;
    try {
      final old = _points;
      _points = await _service.oneTimeBonus(actionKey, bonus);
      if (!_disposed) notifyListeners();
      return _points > old;
    } catch (e) {
      dlog('[POINTS] oneTimeBonus error: $e');
      return false;
    }
  }

  /// Reward koin untuk upload foto galeri slot 1..5 (sekali per slot).
  /// Return jumlah koin yang bertambah (0 jika tidak dapat).
  Future<int> rewardPhotoSlot(int slotIndex) async {
    if (!enabled) return 0;
    try {
      final old = _points;
      _points = await _service.rewardPhotoSlot(slotIndex);
      if (!_disposed) notifyListeners();
      return _points > old ? _points - old : 0;
    } catch (e) {
      dlog('[POINTS] rewardPhotoSlot error: $e');
      return 0;
    }
  }

  /// Buka foto terkunci. mode 'once' | 'perm'. Return true jika sukses.
  Future<bool> unlockPhoto(String photoId, String mode) async {
    try {
      final res = await _service.unlockPhoto(photoId, mode);
      if (res['points'] != null) setPoints((res['points'] as num).toInt());
      return res['ok'] == true;
    } on PostgrestException catch (e) {
      // Server (ledger_spend_dual) melempar 'Not enough points' saat saldo
      // tidak cukup. Fitur topup dihapus — UI menampilkan dialog poin kurang.
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
      if (!_disposed) notifyListeners();
      return _points > old;
    } catch (e) {
      dlog('[POINTS] registerBonus error: $e');
      return false;
    }
  }

  /// Subscribe creator (paid-only). Lempar exception bila gagal.
  Future<Map<String, dynamic>> subscribeCreator(
    String creatorUid, {
    int periods = 1,
  }) async {
    final res = await _service.subscribeCreator(creatorUid, periods: periods);
    await refreshWallet();
    return res;
  }

  /// Klaim reward referral-install (sekali per referred).
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
    // Penjaga terpusat: SEMUA toast koin (bonus, kirim, gift, misi, streak,
    // online) lewat sini. Saat sistem OFF — termasuk untuk admin (server
    // masih memberi bonus via bypass zunixe agar bisa diuji) — jangan
    // tampilkan apa pun supaya tidak dikira bug.
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
        builder: (_) => _PointsToast(
          message: message,
          isError: isError,
          onDismiss: removeOnce,
        ),
      );
      overlay.insert(entry);
      // Safety net: kalau widget tidak sempat dismiss sendiri (mis. overlay
      // lain menutupi), paksa lepas setelah 2s. Idempotent via removeOnce.
      Future.delayed(const Duration(milliseconds: 2000), removeOnce);
    } catch (e) {
      dlog('[PointsProvider] showPointsToast ignored: $e');
    }
  }

  void showOutOfPointsDialog(BuildContext context, bool isId) {
    // Saat sistem OFF tidak ada biaya kirim — dialog "koin habis" tidak
    // relevan. Cegah muncul dari jalur basi (flag lama / antrean offline).
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(s.yukcoinTopupSoon)),
                    );
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


  @override
  void dispose() {
    _disposed = true;
    _enabledSub?.cancel();
    _pointsSub?.cancel();
    _authSub?.cancel();
    _walletDebounce?.cancel();
    _onlineTickTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class _PointsToast extends StatefulWidget {
  final String message;
  final bool isError;
  final VoidCallback onDismiss;
  const _PointsToast({
    required this.message,
    this.isError = false,
    required this.onDismiss,
  });

  @override
  State<_PointsToast> createState() => _PointsToastState();
}

class _PointsToastState extends State<_PointsToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -0.3),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    Future.delayed(
      const Duration(seconds: 1),
      () => _ctrl.reverse().then((_) {
        if (mounted) widget.onDismiss();
      }),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 100,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: widget.isError
                      ? Colors.red.shade700
                      : const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  widget.message,
                  style: AppText.bodySmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
