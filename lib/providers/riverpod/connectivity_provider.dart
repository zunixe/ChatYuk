import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../utils.dart';

/// Status koneksi global (Riverpod) — dipakai banner offline di atas semua
/// layar + guard aksi (flush outbox saat kembali online).
///
/// Migrasi dari ChangeNotifier (Provider) → Notifier. Global (TANPA
/// autoDispose): status koneksi harus hidup sepanjang sesi.
///
/// Side-effect lama di constructor (check awal + subscribe + timer
/// revalidasi) dipindah ke `build()` + `ref.onDispose` — supaya subscribe
/// tak dobel saat provider di-rebuild.
class ConnectivityNotifier extends Notifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _revalidateTimer;

  @override
  bool build() {
    // Nilai awal online=true — jangan tampil banner salah saat cold start.
    // Dijalankan via microtask agar tak memicu modifikasi state saat build.
    Future.microtask(_recheck);
    _sub = Connectivity().onConnectivityChanged.listen(
      _apply,
      onError: (e) => dlog('[Connectivity] stream error: $e'),
    );
    // Pengaman "stuck offline": cek awal bisa menangkap `none` sesaat lalu
    // tak ada event lagi → banner nyangkut. Revalidasi berkala murah.
    _revalidateTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _recheck(),
    );
    ref.onDispose(() {
      _revalidateTimer?.cancel();
      _sub?.cancel();
    });
    return true;
  }

  void _apply(List<ConnectivityResult> results) {
    final online = !results.contains(ConnectivityResult.none);
    if (online == state) return;
    state = online;
  }

  Future<void> _recheck() async {
    try {
      final r = await Connectivity().checkConnectivity();
      _apply(r);
    } catch (_) {}
  }

  /// Revalidasi manual (dipanggil saat app resume).
  void revalidate() => _recheck();
}

final connectivityProvider =
    NotifierProvider<ConnectivityNotifier, bool>(ConnectivityNotifier.new);
