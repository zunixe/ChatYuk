import 'package:facebook_app_events/facebook_app_events.dart';

import '../config/meta_config.dart';
import '../utils.dart';

/// Wrapper Meta App Events (pengukuran install untuk FB Ads).
///
/// Event `Install` + `App Launch` (`fb_mobile_activate_app`, yang dipakai
/// optimasi Install di Ads Manager) dikirim otomatis oleh native SDK.
/// Tanpa App ID terisi -> no-op total.
class MetaAnalytics {
  MetaAnalytics._();

  static bool _done = false;

  /// Panggil sekali dari bootstrap (fire-and-forget, tidak block TTI).
  static Future<void> init() async {
    if (_done || !MetaConfig.isConfigured) return;
    _done = true;
    try {
      await FacebookAppEvents().activateApp();
      dlog('[META] app-activate logged');
    } catch (e) {
      dlog('[META] init gagal: $e');
    }
  }
}
