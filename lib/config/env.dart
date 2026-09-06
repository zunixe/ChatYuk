/// Environment config — satu titik sumber nilai per environment.
///
/// Cara kerja: nilai dibaca dari --dart-define saat build/run.
/// Kalau tidak di-define (build prod biasa), fallback ke konstanta prod
/// di bawah — jadi perilaku build lama TIDAK berubah.
///
/// Dev (Supabase local):
///   flutter run --flavor dev \
///     --dart-define=APP_ENV=dev \
///     --dart-define=SUPABASE_URL=http://localhost:54321 \
///     --dart-define=SUPABASE_ANON_KEY=`<`local-anon-key`>`
///   (Emulator Android pakai http://10.0.2.2:54321, HP fisik USB pakai
///    `adb reverse tcp:54321 tcp:54321` lalu localhost.)
class AppEnv {
  static const String _kEnv = String.fromEnvironment('APP_ENV');
  static const String _kUrl = String.fromEnvironment('SUPABASE_URL');
  static const String _kKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // ── PROD (JANGAN DIUBAH TANPA REVIEW) ──
  static const String prodUrl = 'https://fohcucyyejdryryoxitm.supabase.co';
  static const String prodAnonKey =
      'sb_publishable_aFQQbXscy1mqVq5jHX7p2w_wzs2GAKg';

  static bool get isDev => _kEnv == 'dev';

  static String get supabaseUrl {
    // Guard anti-footgun: build DEV wajib menyertakan URL eksplisit.
    // Tanpa ini, fallback prod membuat app dev diam-diam baca-tulis
    // database production.
    if (isDev && _kUrl.isEmpty) {
      throw StateError(
        'APP_ENV=dev membutuhkan --dart-define=SUPABASE_URL '
        '(app dev TIDAK BOLEH menyentuh prod). '
        'Gunakan tool/run_dev.sh.',
      );
    }
    return _kUrl.isNotEmpty ? _kUrl : prodUrl;
  }

  static String get supabaseAnonKey {
    if (isDev && _kKey.isEmpty) {
      throw StateError(
        'APP_ENV=dev membutuhkan --dart-define=SUPABASE_ANON_KEY '
        '(app dev TIDAK BOLEH menyentuh prod). '
        'Gunakan tool/run_dev.sh.',
      );
    }
    return _kKey.isNotEmpty ? _kKey : prodAnonKey;
  }
}
