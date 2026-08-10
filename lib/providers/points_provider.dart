import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/points_service.dart';

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

  int get points => _points;
  bool get enabled => _enabled;

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

  Future<void> showOnboardingIfNeeded(BuildContext context, bool isId) async {
    // Tunggu fetch flag selesai dulu supaya popup tidak muncul saat disabled
    await refreshEnabled();
    if (_onboardingShown || !_enabled) return;
    if (!context.mounted) return;
    markOnboardingShown();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2E),
        title: Row(children: [
          Text(isId ? '🪙 Sistem Poin ChatYuk' : '🪙 ChatYuk Points', style: const TextStyle(color: Colors.white)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _onboardItem('💬', isId ? 'Chat = pakai poin (-1 per pesan)' : 'Chat = uses points (-1 per msg)'),
            _onboardItem('📅', isId ? 'Login tiap hari = +25 poin' : 'Daily login = +25 points'),
            _onboardItem('⏱️', isId ? 'Online 60 menit = +45 bonus' : 'Online 60 min = +45 bonus'),
            _onboardItem('📧', isId ? 'Daftar email = +100 + AMAN!' : 'Register email = +100 + SAFE!'),
            const SizedBox(height: 4),
            Text(isId ? '🎉 Mulai dengan 50 poin gratis' : '🎉 Start with 50 free points',
              style: const TextStyle(color: Colors.amber, fontSize: 13)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text(isId ? 'OK, Paham!' : 'OK, Got it!', style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _onboardItem(String emoji, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13))),
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
    final label = labels[_lastToastMsg!] ?? '';
    final msg = _lastToastMsg;
    _lastToastMsg = null;
    if (label.isNotEmpty) {
      final pts = {'online_5min': 5, 'online_30min': 10, 'online_60min': 15, 'online_120min': 15};
      showPointsToast(context, isId ? '+${pts[msg!]} Poin — $label' : '+${pts[msg!]} Points — $label');
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
      _points = await _service.dailyLoginBonus();
      resetOnlineTrackers();
      if (!_disposed) notifyListeners();
      if (_points > old) {
        debugPrint('[POINTS] dailyLoginBonus +${_points - old} -> $_points');
      }
    } catch (e) {
      debugPrint('[POINTS] dailyLoginBonus error: $e');
    }
  }

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
      return _points;
    } catch (e) {
      debugPrint('[POINTS] deduct error: $e');
      return _points;
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

  void showPointsToast(BuildContext context, String message, {bool isError = false}) {
    try {
      final overlay = Overlay.of(context);
      late OverlayEntry entry;
      entry = OverlayEntry(
        builder: (_) => _PointsToast(message: message, isError: isError, onDismiss: () {
          try { entry.remove(); } catch (_) {}
        }),
      );
      overlay.insert(entry);
      Future.delayed(const Duration(milliseconds: 2000), () {
        try { entry.remove(); } catch (_) {}
      });
    } catch (_) {}
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
                style: const TextStyle(color: Colors.orange, fontSize: 12)),
              const SizedBox(height: 8),
              Text(isId ? 'Dapatkan sekarang:' : 'Get now:',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
            Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
              child: Text(pts, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
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
        Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 13))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
          child: Text(pts, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _enabledSub?.cancel();
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
    Future.delayed(const Duration(seconds: 1), () => _ctrl.reverse().then((_) => widget.onDismiss()));
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
                child: Text(widget.message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
