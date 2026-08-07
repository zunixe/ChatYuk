import 'package:flutter/services.dart';

/// Anti-screenshot: aktifkan FLAG_SECURE pada window Android.
/// Setelah dipanggil sekali, seluruh app (termasuk chat & foto)
/// tidak bisa di-capture / di-record oleh user.
class ScreenSecureService {
  static const MethodChannel _channel = MethodChannel('com.chatyuk.chatyuk/window');

  static Future<void> enable() async {
    try {
      await _channel.invokeMethod('setSecure');
    } catch (_) {
      // Platform selain Android (iOS/web) tidak punya channel ini — abaikan.
    }
  }

  static Future<void> disable() async {
    try {
      await _channel.invokeMethod('clearSecure');
    } catch (_) {}
  }
}