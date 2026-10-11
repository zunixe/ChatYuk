import 'package:flutter/services.dart';

import '../utils.dart';

/// Battery Saver exemption (gaya WhatsApp).
///
/// MASALAH: di mode Battery Saver (khususnya MIUI), Android membatasi app:
/// refresh dikunci 60Hz + jaringan latar di-throttle (Doze/App-Standby) → UI
/// terasa lag. WhatsApp lolos karena ada di whitelist sistem (MIUI BCBC) +
/// minta `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. ChatYuk dulu TIDAK minta →
/// jadi lambat saat battery saver ON.
///
/// Service ini: cek status + minta exemption (dialog sistem). Dipanggil SEKALI
/// saat startup pertama (lihat main.dart) — TIDAK memaksa; user boleh tolak.
class BatteryOptimizationService {
  BatteryOptimizationService._();

  static const MethodChannel _channel = MethodChannel(
    'com.chatyuk.chatyuk/window',
  );

  /// True bila app sudah dikecualikan dari optimasi baterai (tidak di-throttle).
  static Future<bool> isIgnoring() async {
    try {
      final r = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return r ?? false;
    } catch (e) {
      dlog('[Battery] isIgnoring error: $e');
      return false;
    }
  }

  /// Buka dialog sistem minta exemption. Return true bila intent terkirim.
  static Future<bool> requestIgnore() async {
    try {
      final r = await _channel.invokeMethod<bool>('requestIgnoreBatteryOptimizations');
      return r ?? false;
    } catch (e) {
      dlog('[Battery] requestIgnore error: $e');
      return false;
    }
  }
}
