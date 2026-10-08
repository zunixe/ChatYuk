import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../config/supabase_config.dart';
import '../../utils.dart';

/// Status koneksi global (Riverpod) — dipakai banner offline di atas semua
/// layar + guard aksi (flush outbox saat kembali online).
///
/// PENTING (fix banner nyangkut): `connectivity_plus` di sebagian device
/// (mis. MIUI/HyperOS dengan WiFi tanpa validasi internet, ATAU SDM) KELIRU
/// melaporkan `none` walau internet sebenarnya lancar. Dulu kita langsung
/// percaya hasil OS → banner "Tidak ada koneksi internet" nyangkut padahal
/// RPC jalan. Sekarang: bila OS bilang `none`, kita VERIFIKASI dengan
/// heartbeat HTTP ringan ke Supabase; kalau berhasil → tetap online.
class ConnectivityNotifier extends Notifier<bool> {
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _revalidateTimer;
  bool _probing = false;

  @override
  bool build() {
    // Nilai awal online=true — jangan tampil banner salah saat cold start.
    Future.microtask(_recheck);
    _sub = Connectivity().onConnectivityChanged.listen(
      _apply,
      onError: (e) => dlog('[Connectivity] stream error: $e'),
    );
    // Pengaman "stuck offline": revalidasi berkala murah.
    _revalidateTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _recheck(),
    );
    ref.onDispose(() {
      _revalidateTimer?.cancel();
      _sub?.cancel();
    });
    return true;
  }

  /// Hasil stream OS. Bila OS bilang `none`, JANGAN langsung set offline —
  /// verifikasi dulu (OS sering salah). Bila OS bilang ADA koneksi → online
  /// langsung (tidak perlu probe).
  void _apply(List<ConnectivityResult> results) {
    final osOnline = !results.contains(ConnectivityResult.none);
    if (osOnline) {
      _set(true);
    } else {
      // OS keliru → probe nyata sebelum menyatakan offline.
      unawaited(_verifyThenSetOffline());
    }
  }

  Future<void> _verifyThenSetOffline() async {
    if (_probing) return;
    _probing = true;
    try {
      final reachable = await _reachable();
      _set(reachable);
    } finally {
      _probing = false;
    }
  }

  /// Heartbeat ringan: HEAD ke endpoint Supabase. True bila ada respons HTTP
  /// (status apa pun = server terjangkau = internet hidup).
  Future<bool> _reachable() async {
    // Hook test: bila di-set, pakai itu (tanpa HTTP nyata).
    final override = reachableOverrideForTest;
    if (override != null) return override();
    return _reachableHttp();
  }

  /// Boleh di-override test supaya tidak menembak jaringan nyata.
  @visibleForTesting
  static Future<bool> Function()? reachableOverrideForTest;

  Future<bool> _reachableHttp() async {
    try {
      final uri = Uri.parse('${SupabaseConfig.url}/auth/v1/health');
      final res = await http
          .get(uri, headers: {'apikey': SupabaseConfig.publishableKey})
          .timeout(const Duration(seconds: 4));
      dlog('[Connectivity] probe supabase status=${res.statusCode}');
      return res.statusCode > 0;
    } catch (e) {
      dlog('[Connectivity] probe supabase gagal: $e');
      // Coba DNS umum sebagai cadangan terakhir.
      try {
        final r = await http
            .get(Uri.parse('https://www.gstatic.com/generate_204'))
            .timeout(const Duration(seconds: 4));
        dlog('[Connectivity] probe gstatic status=${r.statusCode}');
        return r.statusCode > 0;
      } catch (e2) {
        dlog('[Connectivity] probe gstatic gagal: $e2');
        return false;
      }
    }
  }

  void _set(bool online) {
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
