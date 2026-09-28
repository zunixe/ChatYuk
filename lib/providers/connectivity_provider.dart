import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../utils.dart';

/// Status koneksi global — dipakai banner offline di atas semua layar.
///
/// connectivity_plus hanya melaporkan interface (wifi/mobile/none):
/// WiFi terhubung tanpa internet tetap "online" — cukup untuk UX banner;
/// realtime error recovery sudah ditangani rt_resilient.
class ConnectivityProvider extends ChangeNotifier {
  bool _online = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _revalidateTimer;
  bool _disposed = false;

  bool get online => _online;

  ConnectivityProvider() {
    // Nilai awal — jangan tampil banner salah saat cold start.
    _recheck();
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      _apply(results);
    }, onError: (e) => dlog('[Connectivity] stream error: $e'));
    // Pengaman "stuck offline": cek awal bisa menangkap `none` sesaat
    // (handover WiFi/seluler) lalu tak ada event perubahan lagi → banner
    // offline nyangkut selamanya padahal internet ada. Revalidasi berkala
    // murah (tanpa I/O, hanya baca status interface) menyembuhkan sendiri.
    _revalidateTimer =
        Timer.periodic(const Duration(seconds: 45), (_) => _recheck());
  }

  void _apply(List<ConnectivityResult> results) {
    final online = !results.contains(ConnectivityResult.none);
    if (online == _online) return;
    _online = online;
    notifyListeners();
  }

  Future<void> _recheck() async {
    try {
      final r = await Connectivity().checkConnectivity();
      if (_disposed) return;
      _apply(r);
    } catch (_) {}
  }

  /// Revalidasi manual (dipanggil saat app resume) — jangan andalkan event
  /// perubahan jaringan yang mungkin tak pernah datang.
  void revalidate() => _recheck();

  @override
  void dispose() {
    _disposed = true;
    _revalidateTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
