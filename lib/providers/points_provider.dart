import 'dart:async';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/points_service.dart';
import '../config/app_flavor.dart';
import '../config/theme.dart';

class PointsProvider extends ChangeNotifier with WidgetsBindingObserver {
  final PointsService _service = PointsService(Supabase.instance.client);
  int _points = 50;
  bool _disposed = false;
  int _todayOnlineSeconds = 0;
  DateTime? _sessionStart;
  bool _claimed5min = false;
  bool _claimed30min = false;
  bool _claimed60min = false;
  bool _claimed120min = false;
  Timer? _onlineTickTimer;
  bool _onboardingShown = false;
  bool _enabled = true;
  StreamSubscription<bool>? _enabledSub;
  StreamSubscription<int>? _pointsSub;
  StreamSubscription<AuthState>? _authSub;
  Timer? _walletDebounce;

  int get points => _points;

  // Mode development: admin (developer) tetap melihat & bisa menguji sistem
  // koin walau app_settings.points_enabled = false di production.
  bool _adminDev = false;

  /// Sistem koin aktif untuk user ini (nilai server ATAU admin/developer).
  bool get enabled => _enabled || _adminDev;
  int get loginStreak => _loginStreak;
  int _loginStreak = 0;
  int _lastStreakBonus = 0;

  // Wallet 3 bucket (Fase 1). _points tetap = total (kompat UI lama).
  int _bonusBalance = 0;
  int _topupBalance = 0;
  int _earnedBalance = 0;
  int get bonusBalance => _bonusBalance;
  int get topupBalance => _topupBalance;
  int get earnedBalance => _earnedBalance;
  int get withdrawableBalance => _earnedBalance;

  /// Saldo "pro" (topup + earned) — koin yang bisa dipakai untuk fitur
  /// berbayar (kirim koin, gift, room private, subscribe, buka foto).
  int get paidBalance => _topupBalance + _earnedBalance;

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

  /// Ambil harga room dari server (dipanggil saat buka lobby).
  Future<void> refreshRoomPricing() async {
    try {
      final p = await _service.roomPricing();
      _roomCreatePaid = (p['create_paid'] as num?)?.toInt() ?? _roomCreatePaid;
      _roomCreatePwPaid = (p['create_pw_paid'] as num?)?.toInt() ?? _roomCreatePwPaid;
      _roomJoinPaid = (p['join_paid'] as num?)?.toInt() ?? _roomJoinPaid;
      _roomExtendPaid = (p['extend_paid'] as num?)?.toInt() ?? _roomExtendPaid;
      _bonusMultiplier = (p['multiplier'] as num?)?.toInt() ?? _bonusMultiplier;
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('[POINTS] refreshRoomPricing error: $e');
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
      debugPrint('[POINTS] refreshPhotoCosts error: $e');
    }
  }

  /// Ambil saldo wallet 3 bucket dari server (RPC get_wallet).
  Future<void> refreshWallet() async {
    try {
      final w = await _service.getWallet();
      _bonusBalance = (w['bonus'] as num?)?.toInt() ?? 0;
      _topupBalance = (w['topup'] as num?)?.toInt() ?? 0;
      _earnedBalance = (w['earned'] as num?)?.toInt() ?? 0;
      _points = (w['total'] as num?)?.toInt() ?? _points;
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('[POINTS] getWallet error: $e');
    }
  }

  PointsProvider() {
    // Daftarkan observer + mulai sesi online SEKARANG. Tanpa ini,
    // didChangeAppLifecycleState tidak pernah terpanggil (observer tak
    // terdaftar) sehingga bonus online tidak pernah jalan, dan sesi
    // pertama (cold start) tidak terhitung.
    WidgetsBinding.instance.addObserver(this);
    _sessionStart = DateTime.now();
    _onlineTickTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _checkOnlineMilestones());
    // Sinkron saldo koin via realtime profiles — koin masuk (transfer) &
    // keluar (belanja) langsung tampil tanpa reload.
    subscribeOwnPoints();
    // Saat user berganti (login/logout), stream poin harus di-resubscribe
    // supaya menunjuk ke row profiles yang benar.
    try {
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((state) {
        if (_disposed) return;
        _refreshAdminDev();
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
      });
      _refreshAdminDev();
    } catch (e) {
      debugPrint('[POINTS] auth listener error: $e');
    }
    // Sesi sudah direstore sebelum runApp (Supabase.initialize di main()),
    // event initialSession bisa ter-emit sebelum listener terdaftar sehingga
    // adminDev tidak pernah aktif — cek ulang setelah frame pertama.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshAdminDev());
  }

  /// Mode development: admin (developer) selalu bisa menguji sistem koin,
  /// termasuk saat points_enabled = false di production.
  void _refreshAdminDev() {
    final email = Supabase.instance.client.auth.currentUser?.email;
    final isAdmin = email == AppFlavor.adminEmail;
    if (isAdmin != _adminDev) {
      _adminDev = isAdmin;
      if (!_disposed) notifyListeners();
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
      });
      // Ambil rincian awal saat subscribe
      refreshWallet();
    } catch (e) {
      debugPrint('[POINTS] watchOwnPoints error: $e');
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
        _enabled = value;
        notifyListeners();
      });
    } catch (e) {
      debugPrint('[POINTS] watchEnabled error: $e');
    }
  }

  Future<void> refreshEnabled() async {
    try {
      _enabled = await _service.fetchEnabled();
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('[POINTS] fetchEnabled error: $e');
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
    // Tunggu fetch flag selesai dulu supaya popup tidak muncul saat disabled
    await refreshEnabled();
    if (_onboardingShown || !_enabled) return;
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
              child: Row(children: [
                Text('🪙', style: TextStyle(fontSize: AppGlyph.lg)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.pointsOnboardTitle, style: AppText.title.copyWith(color: Colors.white)),
                      Text(s.pointsOnboardSub, style: AppText.caption.copyWith(color: Colors.white70)),
                    ],
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Email +100 — paling atas (di bawah header).
                  _onboardItem('📧', s.pointsOnboardEmail, highlight: true),
                  _onboardItem('💬', s.pointsOnboardChat),
                  _onboardItem('📅', s.pointsOnboardDaily),
                  _onboardItem('⏱️', s.pointsOnboardOnline),
                  const SizedBox(height: 6),
                  Row(children: [
                    Text('🎉', style: TextStyle(fontSize: AppGlyph.sm)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(s.pointsOnboardStart,
                        style: AppText.bodySmall.copyWith(color: Colors.amber)),
                    ),
                  ]),
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
          color: highlight ? const Color(0xFF2ECC71).withValues(alpha: 0.5) : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: Row(children: [
        Text(emoji, style: TextStyle(fontSize: AppGlyph.md)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: AppText.body.copyWith(
            color: highlight ? Colors.white : Colors.white70,
            fontWeight: highlight ? FontWeight.w700 : FontWeight.w400,
          )),
        ),
        if (highlight)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF2ECC71),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('+100', style: AppText.label.copyWith(color: Colors.white)),
          ),
      ]),
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
      _onlineTickTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkOnlineMilestones());
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (_sessionStart != null) {
        _todayOnlineSeconds += DateTime.now().difference(_sessionStart!).inSeconds;
        _sessionStart = null;
      }
      _onlineTickTimer?.cancel();
      _checkOnlineMilestones();
    }
  }

  void _checkOnlineMilestones() {
    if (!_enabled) return;
    if (_sessionStart != null) {
      _todayOnlineSeconds += DateTime.now().difference(_sessionStart!).inSeconds;
      _sessionStart = DateTime.now();
    }
    _tryClaimOnlineBonus();
  }

  Future<void> _tryClaimOnlineBonus() async {
    if (_disposed) return;
    // Note: toast dipanggil oleh caller/dialog — bonus online diketahui via
    // pengecekan poin sebelum/sesudah. Online bonus diklaim diam-diam,
    // user lihat poin naik di AppBar.
    if (!_claimed5min && _todayOnlineSeconds >= 300) {
      _claimed5min = true;
      if (await oneTimeBonus('online_5min', 5)) {
        _lastToastMsg = 'online_5min';
      }
    }
    if (!_claimed30min && _todayOnlineSeconds >= 1800) {
      _claimed30min = true;
      if (await oneTimeBonus('online_30min', 10)) {
        _lastToastMsg = 'online_30min';
      }
    }
    if (!_claimed60min && _todayOnlineSeconds >= 3600) {
      _claimed60min = true;
      if (await oneTimeBonus('online_60min', 15)) {
        _lastToastMsg = 'online_60min';
      }
    }
    if (!_claimed120min && _todayOnlineSeconds >= 7200) {
      _claimed120min = true;
      if (await oneTimeBonus('online_120min', 15)) {
        _lastToastMsg = 'online_120min';
      }
    }
  }

  String? _lastToastMsg;

  void checkAndShowOnlineToast(BuildContext context, bool isId) {
    if (_lastToastMsg == null) return;
    final labels = {
      'online_5min': isId ? 'Online 5 menit' : 'Online 5 min',
      'online_30min': isId ? 'Online 30 menit' : 'Online 30 min',
      'online_60min': isId ? 'Online 60 menit' : 'Online 60 min',
      'online_120min': isId ? 'Online 120 menit' : 'Online 120 min',
    };
    final msg = _lastToastMsg;
    _lastToastMsg = null;
    if (msg == null) return;
    final label = labels[msg] ?? '';
    if (label.isNotEmpty) {
      final pts = {'online_5min': 5, 'online_30min': 5, 'online_60min': 5, 'online_120min': 5};
      final p = pts[msg] ?? 0;
      showPointsToast(context, isId ? '+$p Poin — $label' : '+$p Points — $label');
    }
  }

  void resetOnlineTrackers() {
    _todayOnlineSeconds = 0;
    _claimed5min = false;
    _claimed30min = false;
    _claimed60min = false;
    _claimed120min = false;
  }

  Future<void> claimDailyLogin() async {
    if (!_enabled) return;
    try {
      final old = _points;
      final res = await _service.dailyLoginBonus();
      _points = (res['points'] as num?)?.toInt() ?? _points;
      _loginStreak = (res['streak'] as num?)?.toInt() ?? _loginStreak;
      _lastStreakBonus = (res['bonus'] as num?)?.toInt() ?? 0;
      resetOnlineTrackers();
      if (!_disposed) notifyListeners();
      if (_points > old) {
        debugPrint('[POINTS] dailyLoginBonus +${_points - old} streak=$_loginStreak -> $_points');
      }
    } catch (e) {
      debugPrint('[POINTS] dailyLoginBonus error: $e');
    }
  }

  /// Tampilkan toast streak setelah daily login (dipanggil dari UI yang punya context).
  void checkAndShowStreakToast(BuildContext context, bool isId) {
    if (_lastStreakBonus <= 0) return;
    final bonus = _lastStreakBonus;
    final streak = _loginStreak;
    _lastStreakBonus = 0;
    showPointsToast(context,
        isId ? '🔥 Streak $streak hari — +$bonus Poin' : '🔥 $streak-day streak — +$bonus Points');
  }

  /// Bonus chat orang baru (harian ber-limit, dikelola server).
  Future<bool> newChatBonus(String otherUid) async {
    if (!_enabled) return false;
    try {
      final old = _points;
      _points = await _service.newChatBonus(otherUid);
      if (!_disposed) notifyListeners();
      return _points > old;
    } catch (e) {
      debugPrint('[POINTS] newChatBonus error: $e');
      return false;
    }
  }

  /// Potong poin sebelum kirim pesan. Return:
  ///   >= 0  saldo baru (sukses)
  ///   -1    poin tidak cukup
  ///   -2    error tak dikenal (RPC/network) — JANGAN kirim pesan
  Future<int> deductBeforeSend(String msgType) async {
    if (!_enabled) return _points;
    try {
      final remaining = await _service.deductChatPoint(msgType);
      _points = remaining;
      if (!_disposed) notifyListeners();
      return remaining;
    } on PostgrestException catch (e) {
      if (e.message.contains('Not enough points')) return -1;
      debugPrint('[POINTS] deduct error: $e');
      return -2;
    } catch (e) {
      debugPrint('[POINTS] deduct error: $e');
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
      debugPrint('[POINTS] refundChatPoint error: $e');
    }
  }

  Future<void> roomReadBonus() async {
    if (!_enabled) return;
    try {
      _points = await _service.roomReadBonus();
      if (!_disposed) notifyListeners();
    } catch (e) {
      debugPrint('[POINTS] roomReadBonus error: $e');
    }
  }

  Future<bool> oneTimeBonus(String actionKey, int bonus) async {
    if (!_enabled) return false;
    try {
      final old = _points;
      _points = await _service.oneTimeBonus(actionKey, bonus);
      if (!_disposed) notifyListeners();
      return _points > old;
    } catch (e) {
      debugPrint('[POINTS] oneTimeBonus error: $e');
      return false;
    }
  }

  /// Reward koin untuk upload foto galeri slot 1..5 (sekali per slot).
  /// Return jumlah koin yang bertambah (0 jika tidak dapat).
  Future<int> rewardPhotoSlot(int slotIndex) async {
    if (!_enabled) return 0;
    try {
      final old = _points;
      _points = await _service.rewardPhotoSlot(slotIndex);
      if (!_disposed) notifyListeners();
      return _points > old ? _points - old : 0;
    } catch (e) {
      debugPrint('[POINTS] rewardPhotoSlot error: $e');
      return 0;
    }
  }

  /// Buka foto terkunci. mode 'once' | 'perm'. Return true jika sukses.
  /// Lempar 'topup' bila koin topup kurang (untuk dialog top up).
  Future<bool> unlockPhoto(String photoId, String mode) async {
    try {
      final res = await _service.unlockPhoto(photoId, mode);
      if (res['points'] != null) setPoints((res['points'] as num).toInt());
      return res['ok'] == true;
    } on PostgrestException catch (e) {
      // Server (ledger_spend_dual) melempar 'Not enough points' — bukan
      // 'Not enough topup' (pesan lama) — saat saldo bonus pun tidak cukup.
      if (e.message.contains('Not enough points') ||
          e.message.contains('Not enough topup')) {
        throw 'topup';
      }
      debugPrint('[POINTS] unlockPhoto error: $e');
      rethrow;
    }
  }

  Future<bool> claimRegisterBonus() async {
    if (!_enabled) return false;
    try {
      final old = _points;
      _points = await _service.registerBonus();
      if (!_disposed) notifyListeners();
      return _points > old;
    } catch (e) {
      debugPrint('[POINTS] registerBonus error: $e');
      return false;
    }
  }

  /// Subscribe creator (paid-only). Lempar exception bila gagal.
  Future<Map<String, dynamic>> subscribeCreator(String creatorUid, {int periods = 1}) async {
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

  void showPointsToast(BuildContext context, String message, {bool isError = false}) {
    try {
      final overlay = Overlay.of(context);
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (_) => _PointsToast(message: message, isError: isError, onDismiss: () {
          try { entry.remove(); } catch (e) { debugPrint('[PointsProvider] showPointsToast ignored: $e'); }
        }),
      );
      overlay.insert(entry);
      Future.delayed(const Duration(milliseconds: 2000), () {
        try { entry.remove(); } catch (e) { debugPrint('[PointsProvider] showPointsToast ignored: $e'); }
      });
    } catch (e) { debugPrint('[PointsProvider] showPointsToast ignored: $e'); }
  }

  void showOutOfPointsDialog(BuildContext context, bool isId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Text(isId ? '😢 Poin Habis!' : '😢 Out of Points!', style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(isId ? 'Akun anonim: poin bisa hilang kapan saja!' : 'Anonymous account: points can be lost!',
                style: AppText.bodySmall.copyWith(color: Colors.orange)),
              const SizedBox(height: 8),
              Text(isId ? 'Dapatkan sekarang:' : 'Get now:',
                style: AppText.bodySmall.copyWith(color: Colors.white70)),
              const SizedBox(height: 6),
              _dialogBtn(ctx, isId, '📧 ${isId ? "Daftar Email" : "Register Email"}', '+100', Colors.green, () {
                Navigator.of(ctx).pop();
              }),
              _dialogBtn(ctx, isId, '⭐ ${isId ? "Rate ChatYuk" : "Rate ChatYuk"}', '+20', Colors.blue, () async {
                Navigator.of(ctx).pop();
                final earned = await oneTimeBonus('rated_app', 20);
                if (earned && context.mounted) {
                  showPointsToast(context, isId ? '+20 Poin — Rate app!' : '+20 Points — Rate app!');
                }
              }),
              _dialogBtn(ctx, isId, '📢 ${isId ? "Share ke Teman" : "Share App"}', '+10', Colors.teal, () async {
                Navigator.of(ctx).pop();
                await Share.share(isId ? 'Ayo chat bareng di ChatYuk! Download di Play Store: https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk' : 'Chat freely on ChatYuk! Download on Play Store: https://play.google.com/store/apps/details?id=com.chatyuk.chatyuk');
                final earned = await oneTimeBonus('shared_app', 10);
                if (earned && context.mounted) {
                  showPointsToast(context, isId ? '+10 Poin — Share app!' : '+10 Points — Share app!');
                }
              }),
              _dialogBtn(ctx, isId, '📝 ${isId ? "Lengkapi Profil" : "Complete Profile"}', '+10', Colors.orange, () async {
                Navigator.of(ctx).pop();
                final earned = await oneTimeBonus('completed_profile', 10);
                if (earned && context.mounted) {
                  showPointsToast(context, isId ? '+10 Poin — Profil!' : '+10 Points — Profile!');
                }
              }),
              _dialogBtn(ctx, isId, '📸 ${isId ? "Kirim Foto Pertama" : "Send First Photo"}', '+10', Colors.pink, () async {
                Navigator.of(ctx).pop();
                final earned = await oneTimeBonus('first_photo', 10);
                if (earned && context.mounted) {
                  showPointsToast(context, isId ? '+10 Poin — Foto pertama!' : '+10 Points — First photo!');
                }
              }),
              const Divider(color: Colors.white24),
              Text(isId ? 'Gratis besok:' : 'Free tomorrow:',
                style: AppText.bodySmall.copyWith(color: Colors.white70)),
              const SizedBox(height: 4),
              _dialogAction(isId, '📅 ${isId ? "Login Besok" : "Login Tomorrow"}', '+25', Colors.amber),
              _dialogAction(isId, '📖 ${isId ? "Baca Room" : "Read Room"}', '+2', Colors.grey),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(isId ? 'Tutup' : 'Close', style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _dialogBtn(BuildContext ctx, bool isId, String label, String pts, Color color, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(children: [
            Expanded(child: Text(label, style: AppText.bodySmall.copyWith(color: Colors.white))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
              child: Text(pts, style: AppText.label.copyWith(color: color, letterSpacing: 0, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
          ]),
        ),
      ),
    );
  }

  Widget _dialogAction(bool isId, String label, String pts, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Expanded(child: Text(label, style: AppText.bodySmall.copyWith(color: Colors.white))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
          child: Text(pts, style: AppText.label.copyWith(color: color, letterSpacing: 0, fontWeight: FontWeight.w700)),
        ),
      ]),
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
  const _PointsToast({required this.message, this.isError = false, required this.onDismiss});

  @override
  State<_PointsToast> createState() => _PointsToastState();
}

class _PointsToastState extends State<_PointsToast> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  late final Animation<Offset> _slide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
    .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
  late final Animation<double> _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 1), () => _ctrl.reverse().then((_) { if (mounted) widget.onDismiss(); }));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 100, left: 0, right: 0,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: widget.isError ? Colors.red.shade700 : const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Text(widget.message, style: AppText.bodySmall.copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
