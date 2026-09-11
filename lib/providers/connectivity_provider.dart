import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Status koneksi global — dipakai banner offline di atas semua layar.
///
/// connectivity_plus hanya melaporkan interface (wifi/mobile/none):
/// WiFi terhubung tanpa internet tetap "online" — cukup untuk UX banner;
/// realtime error recovery sudah ditangani rt_resilient.
class ConnectivityProvider extends ChangeNotifier {
  bool _online = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  bool get online => _online;

  ConnectivityProvider() {
    // Nilai awal — jangan tampil banner salah saat cold start.
    Connectivity().checkConnectivity().then((r) {
      _online = !r.contains(ConnectivityResult.none);
      notifyListeners();
    });
    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final online = !results.contains(ConnectivityResult.none);
      if (online == _online) return;
      _online = online;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
