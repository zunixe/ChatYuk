import 'package:shared_preferences/shared_preferences.dart';

/// Preferensi default kualitas foto kiriman (ala WhatsApp:
/// Settings → Storage → Media upload quality).
/// true = toggle HD di preview default ON; false = Standard.
class PhotoQualityPref {
  static const String _key = 'photo_quality_hd';

  static Future<bool> get defaultHd async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setDefaultHd(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }
}
