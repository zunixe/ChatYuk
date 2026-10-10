import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

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
/// SOLUSI: selama app di FOREGROUND, kirim 1 repaint murah tiap [interval]
///   agar SurfaceFlinger melihat surface ini AKTIF dan tidak mengunci panel ke
///   mode DDIC idle. Interval default dibuat JAUH di bawah 70 ms (batas Idle
///   Timeout panel) tapi tidak 60 fps penuh — hemat daya, cukup anti-idle.
///
/// Hemat: TIDAK render saat app di background/paused (tidak menaikkan
/// konsumsi saat user keluar).
class RenderHeartbeat extends StatefulWidget {
  /// Widget yang dibungkus (subtree app).
  final Widget child;

  /// Jarak antar "denyut" di foreground. Harus < ~70ms agar tidak kena
  /// SDM Idle Timeout; 56ms (~18 fps) memberi margin aman (~14ms di bawah
  /// batas) sambil jauh lebih hemat daya daripada 32ms/60fps-penuh.
  final Duration interval;

  const RenderHeartbeat({
    super.key,
    required this.child,
    this.interval = const Duration(milliseconds: 56),
  });

  @override
  State<RenderHeartbeat> createState() => _RenderHeartbeatState();
}

class _RenderHeartbeatState extends State<RenderHeartbeat>
    with WidgetsBindingObserver {
  Timer? _timer;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = WidgetsBinding.instance.lifecycleState ??
        AppLifecycleState.resumed;
    if (_lifecycle == AppLifecycleState.resumed) _start();
  }

  @override
  void dispose() {
    _stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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

  void _start() {
    if (_timer != null) return;
    // Timer-based (bukan Ticker) → hanya membangunkan engine saat interval,
    // bukan tiap vsync, sehingga biaya CPU jauh lebih kecil dari 60 fps penuh.
    _timer = Timer.periodic(widget.interval, (_) {
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
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
