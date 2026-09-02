import 'package:flutter/services.dart';

/// Kirim sinyal ke native (MainActivity) untuk fade-out overlay anti-blink.
/// Overlay gelap dipasang native sejak onCreate — menutupi task snapshot
/// HyperOS yang stale-terang + frame abu renderer saat first-paint.
/// Dipanggil SETELAH konten utama first-frame (bukan skeleton) supaya
/// user langsung melihat konten, bukan layar hitam.
class BootOverlay {
  static const _channel = MethodChannel('com.chatyuk.chatyuk/window');
  static bool _done = false;

  static void hide() {
    if (_done) return;
    _done = true;
    try {
      _channel.invokeMethod('hideBootOverlay');
    } catch (_) {
      // Platform tidak punya handler (mis. iOS) — abaikan.
    }
  }
}
