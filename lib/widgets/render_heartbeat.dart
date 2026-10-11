import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../core/nav_visibility.dart';

/// Heartbeat render — mencegah panel masuk "DDIC idle" di MIUI/Xiaomi.
///
/// MASALAH (terukur via atrace + dumpsys SurfaceFlinger):
///   Saat halaman chat DIAM (idle), Flutter berhenti men-submit frame
///   (terukur: 0 frame / 5 detik). MIUI lalu menganggap app idle
///   (`isTpIdleScene, mAverageFrameRate is 0`) dan memindah panel ke mode
///   `ddic_mode=1, ddic_min_fps=1` (boleh turun ke 1Hz) + terus-menerus
///   "SDM Idle Timeout 70ms". Akibatnya vsync jadi lambat (~500ms) dan frame
///   PERTAMA saat bangun dari idle tertahan ~0.5–1.9 detik — inilah yang
///   dirasa "ngelag buka private chat setelah dari background".
///
///   Bandingkan app sejenis: Telegram saat diam TETAP render ~61 fps
///   (gfxinfo: 306 frame / 5 s) → panel tetap mode {normal} → 0 idle timeout
///   → mulus saat dibuka lagi.
///
/// SOLUSI: selama app di FOREGROUND, kirim repaint murah agar SurfaceFlinger
///   melihat surface ini AKTIF dan tidak mengunci panel ke DDIC idle.
///
/// OPTIMASI BATERAI (2026-10-11): dulu interval 56ms TERUS-MENERUS di semua
/// tab → ~18 fps repaint tanpa henti = konsumsi baterai besar (terukur CPU
/// app 744 vs WhatsApp 363 di batterystats). Sekarang ADAPTIF:
///   - Tab yang BUTUH responsivitas buka-chat (Online=0 / Chat=1 / grup-room)
///     → interval cepat (anti DDIC idle di surface yang sering dibuka).
///   - Tab lain (Timeline=2 / Profil=3) → interval lambat (tetap anti-idle,
///     jauh lebih hemat; tab ini jarang jadi "target buka chat").
///   - App background → STOP (sudah; tak menambah konsumsi saat keluar).
///
/// Hemat: TIDAK render saat app di background/paused.
class RenderHeartbeat extends StatefulWidget {
  /// Widget yang dibungkus (subtree app).
  final Widget child;

  /// Jarak antar "denyut" di tab yang butuh responsif (chat/online).
  /// Harus < ~70ms (batas SDM Idle Timeout panel) — 56ms margin aman.
  final Duration interval;

  /// Interval lebih lambat untuk tab non-chat (Timeline/Profil) — tetap
  /// mencegah DDIC idle tapi repaint jauh lebih jarang (hemat baterai).
  final Duration slowInterval;

  const RenderHeartbeat({
    super.key,
    required this.child,
    this.interval = const Duration(milliseconds: 56),
    this.slowInterval = const Duration(milliseconds: 240),
  });

  @override
  State<RenderHeartbeat> createState() => _RenderHeartbeatState();
}

class _RenderHeartbeatState extends State<RenderHeartbeat>
    with WidgetsBindingObserver {
  Timer? _timer;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  Duration _currentInterval = Duration.zero;

  /// Tab butuh heartbeat cepat: Online(0)/Chat(1) — surface yang sering jadi
  /// target "buka chat". Tab lain (Timeline/Profil) cukup lambat.
  bool get _needsFast => visibleMainTab.value <= 1;

  Duration get _desired =>
      _needsFast ? widget.interval : widget.slowInterval;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState ??
        AppLifecycleState.resumed;
    visibleMainTab.addListener(_onTabChanged);
    if (_lifecycle == AppLifecycleState.resumed) _start();
  }

  @override
  void dispose() {
    visibleMainTab.removeListener(_onTabChanged);
    _stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onTabChanged() {
    // Ganti interval saat pindah tab (cepat ⇄ lambat). Restart timer hanya
    // bila interval benar-benar berubah.
    if (_timer == null) return;
    if (_desired != _currentInterval) _start(force: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _stop();
    }
  }

  void _start({bool force = false}) {
    if (_timer != null && !force) return;
    _timer?.cancel();
    _currentInterval = _desired;
    // Timer-based (bukan Ticker) → hanya membangunkan engine saat interval,
    // bukan tiap vsync, sehingga biaya CPU jauh lebih kecil dari 60 fps penuh.
    _timer = Timer.periodic(_currentInterval, (_) {
      // Mark subtree perlu paint: `markNeedsBuild` pada ValueKey ringan
      // memicu satu frame. Aman: tak mengubah layout/state apa pun.
      final binding = WidgetsBinding.instance;
      if (binding.schedulerPhase == SchedulerPhase.idle) {
        binding.scheduleFrame();
      }
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _currentInterval = Duration.zero;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
