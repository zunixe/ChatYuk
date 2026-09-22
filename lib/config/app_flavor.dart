/// Flavor distribusi build — dibaca dari `--dart-define=APP_FLAVOR`.
///
/// Nilai yang dipakai di perintah build (lihat AGENTS.md "Build & Signing"):
/// - `play`    → build untuk Google Play (AAB). Popup update memakai Play
///               Core In-App Update.
/// - `apkpure` → build APK mandiri (HP/APKPure). TIDAK punya Play Core →
///               popup tetap muncul, tapi tombol membuka listing Play di
///               browser (tidak ada jalur self-install ilegal).
/// - `admin`   → build internal (main_admin.dart). Fitur update DI-SKIP.
///
/// Default `apkpure` agar build tanpa dart-define (mis. dev/test) tidak
/// pernah mengaktifkan jalur Play.
///
/// CATATAN: flavor ini hanya *fast-path*. Sumber kebenaran "apakah app boleh
/// pakai Play Core" tetap deteksi installer runtime (`com.android.vending`)
/// — app build `play` yang di-sideload tetap tidak bisa pakai Play Core.
class AppFlavor {
  AppFlavor._();

  static const String _flavor = String.fromEnvironment(
    'APP_FLAVOR',
    defaultValue: 'apkpure',
  );

  static bool get isPlay => _flavor == 'play';
  static bool get isApkpure => _flavor == 'apkpure';
  static bool get isAdmin => _flavor == 'admin';
}
