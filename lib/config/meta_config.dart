// Konfigurasi Meta App Events (pengukuran install untuk FB Ads).
//
// CARA ISI (sekali saja, sebelum build play yang mau diiklankan):
// 1. Buat Meta App di developers.facebook.com -> catat App ID + Client Token.
// 2. Tulis App ID + Client Token di bawah INI.
// 3. Tulis nilai yang SAMA di
//    android/app/src/main/res/values/strings.xml
//    (facebook_app_id + facebook_client_token).
// 4. Daftarkan key hash keystore v2 + listing Play di dashboard Meta App.
//
// Selama masih placeholder, MetaAnalytics.init() = no-op: build dev,
// apkpure, dan admin tetap jalan normal tanpa kirim apa pun ke Meta.
class MetaConfig {
  // App ID Meta "ChatYuk" (lihat docs/META_APP.md untuk sumbernya).
  static const String appId = '4699753480345190';

  // Client Token dari Settings -> Advanced -> Token Klien.
  static const String clientToken = '782f99654ddbf22be6b59900e08da2ab';

  /// True bila App ID + Client Token sudah diisi (bukan placeholder).
  static bool get isConfigured =>
      appId != '0' && clientToken != 'META_CLIENT_TOKEN';
}
