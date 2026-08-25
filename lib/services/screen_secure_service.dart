import 'package:flutter/services.dart';
import '../core/admin_gate.dart';

/// Anti-screenshot terpusat.
///
/// Aturan (prioritas tinggi ke rendah):
/// 1. [viewOnceActive]  — pesan sekali-lihat SELALU anti-screenshot.
/// 2. [donationActive]  — halaman donasi SELALU bisa screenshot (share QRIS).
/// 3. [screenshotEnabled] — setting admin global. true = bisa screenshot,
///    false = seluruh app anti-screenshot.
class ScreenSecureService {
  static const MethodChannel _channel = MethodChannel(
    'com.chatyuk.chatyuk/window',
  );

  static bool _screenshotEnabled = true;
  static bool _donationActive = false;
  static bool _viewOnceActive = false;

  /// Setting admin: apakah screenshot aplikasi diizinkan (default: ya).
  static bool get screenshotEnabled => _screenshotEnabled;

  static void setScreenshotEnabled(bool enabled) {
    _screenshotEnabled = enabled;
    _apply();
  }

  /// Halaman donasi dibuka — selalu boleh screenshot.
  static void enterDonation() {
    _donationActive = true;
    _apply();
  }

  static void exitDonation() {
    _donationActive = false;
    _apply();
  }

  /// Pesan sekali-lihat sedang dilihat — selalu anti-screenshot.
  static void enterViewOnce() {
    _viewOnceActive = true;
    _apply();
  }

  static void exitViewOnce() {
    _viewOnceActive = false;
    _apply();
  }

  static Future<void> _apply() async {
    // Build ADMIN selalu boleh screenshot — setting global anti-screenshot
    // (untuk ChatYuk user) TIDAK berlaku di app admin.
    if (AdminGate.enabled) {
      try {
        await _channel.invokeMethod('clearSecure');
      } catch (_) {}
      return;
    }
    final secure = _viewOnceActive || (!_donationActive && !_screenshotEnabled);
    try {
      if (secure) {
        await _channel.invokeMethod('setSecure');
      } else {
        await _channel.invokeMethod('clearSecure');
      }
    } catch (_) {
      // Platform selain Android (iOS/web) tidak punya channel ini — abaikan.
    }
  }

  /// Android ID (Settings.Secure.ANDROID_ID) — unik & stabil per perangkat +
  /// app-signing key, tetap sama walau app di-reinstall (kecuali factory reset).
  /// Dipakai sebagai install_id untuk pelacakan device di panel admin.
  /// Return '' di luar Android (iOS/web pakai fallback di DeviceInfoService).
  static Future<String> androidId() async {
    try {
      final res = await _channel.invokeMethod<String>('androidId');
      return res ?? '';
    } catch (_) {
      return '';
    }
  }
}
