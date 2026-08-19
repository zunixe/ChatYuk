/// Konfigurasi flavor distribusi aplikasi.
///
/// Dibedakan lewat `--dart-define=APP_FLAVOR=...`:
///   - apkpure (default): appId `com.chatyuk.chatyuk`.
///   - play (Google Play): appId `com.chatyuk.chatyuk` (sama dengan apkpure), `google-services.json`
///     khusus di `android/app/src/play/`.
///
/// Kedua flavor sekarang memiliki PERILAKU YANG SAMA (app chat + koin sebagai
/// digital goods murni). Fitur finansial (top-up iPaymu/Midtrans, KYC,
/// pencairan/withdraw) telah dihapus total — termasuk dari server.
///
/// Catatan: kode finansial lama masih tersimpan di git tag
/// `archive/financial-features` — lihat `docs/restore-financial-features.md`.
class AppFlavor {
  AppFlavor._();

  static const String name = String.fromEnvironment('APP_FLAVOR', defaultValue: 'apkpure');

  /// Email admin (developer). Admin selalu bisa menguji sistem koin walau
  /// `app_settings.points_enabled = false` di production (server juga
  /// mengecualikan email ini dari guard points_enabled).
  static const String adminEmail = 'zunixe@gmail.com';

  static bool get isPlay => name == 'play';
}
