/// Konfigurasi flavor distribusi aplikasi.
///
/// Dibedakan lewat `--dart-define=APP_FLAVOR=...`:
///   - apkpure (default): fitur penuh — top-up iPaymu + KYC + pencairan.
///   - play (Google Play): kepatuhan Play — top-up & pencairan disembunyikan
///     sampai Google Play Billing dipasang (cash-out virtual currency tidak
///     diizinkan Play untuk app berisi digital goods).
///
/// Catatan keamanan: Play & APKPure berbagi satu Supabase project saat ini.
/// Untuk kepatuhan penuh Play, sebaiknya pisahkan project/DB per store agar
/// coin tidak bisa dipindah lintas store (celah laundering).
class AppFlavor {
  AppFlavor._();

  static const String name = String.fromEnvironment('APP_FLAVOR', defaultValue: 'apkpure');

  /// Email admin (developer). Admin selalu bisa menguji sistem koin walau
  /// `app_settings.points_enabled = false` di production (server juga
  /// mengecualikan email ini dari guard points_enabled).
  static const String adminEmail = 'zunixe@gmail.com';

  static bool get isPlay => name == 'play';

  /// Tampilkan menu pencairan (KYC + Withdraw). Play menyembunyikannya.
  static bool get showCashOut => !isPlay;

  /// Tampilkan menu top-up coin.
  /// Play: belum aktif sampai Google Play Billing terpasang.
  static bool get topupEnabled => !isPlay;

  /// Provider top-up: 'ipaymu' (apkpure) vs 'play_billing' (play, mendatang).
  static String get topupProvider => isPlay ? 'play_billing' : 'ipaymu';
}
