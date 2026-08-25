import 'package:flutter/material.dart';
import 'package:provider/single_child_widget.dart';

/// Jembatan netral antara build USER dan build ADMIN.
///
/// ATURAN WAJIB: file ini TIDAK BOLEH meng-import modul admin mana pun
/// (lib/screens/admin_*, lib/providers/admin_provider.dart, lib/admin/*).
///
/// Build rilis (flavor apkpure/play, entry default `lib/main.dart`) tidak
/// pernah mengisi field di sini → graph import user tidak pernah menyentuh
/// kode admin → tree shaker membuangnya TOTAL dari APK rilis.
/// Entry admin (`lib/main_admin.dart`) mengisi semua field via wireAdmin().
class AdminGate {
  /// Builder halaman Admin Panel. Null pada build user.
  static WidgetBuilder? panelBuilder;

  /// Provider tambahan untuk MultiProvider di app.dart (mis. AdminProvider).
  static List<SingleChildWidget> extraProviders = const [];

  /// Section pengaturan admin di halaman Profil:
  /// [header] = tile buka panel (+divider), sebelum baris Notifikasi.
  /// [tail]   = toggle screenshot/watermark/invisible (+divider),
  ///            sesudah baris Notifikasi.
  static List<Widget> Function(BuildContext)? profileSettingsHeader;
  static List<Widget> Function(BuildContext)? profileSettingsTail;

  /// Banner sesi dummy di halaman Profil (hanya tampil saat sesi dummy).
  /// [nickname] = nama dummy yang sedang aktif.
  static Widget? Function(BuildContext, String? nickname)? dummySessionBanner;

  /// Swap ke akun dummy (uid). Null pada build rilis.
  static Future<void> Function(String uid)? becomeDummyImpl;

  /// Kembali ke akun admin. Return false jika token kedaluwarsa.
  static Future<bool> Function()? backToAdminImpl;

  /// Pulihkan state dummy setelah app restart.
  static Future<void> Function()? restoreDummySession;

  /// Dipanggil bootstrap SETELAH Supabase.initialize — tempat aman untuk
  /// hal yang butuh client Supabase (mis. pasang listener token admin).
  static Future<void> Function()? postInit;

  /// Ada token admin tersimpan di SharedPreferences? (untuk recovery).
  static Future<bool> Function()? hasStoredDummyTokens;

  /// Bersihkan token admin tersimpan saat logout total.
  static Future<void> Function()? onSignOut;

  /// True hanya pada build admin.
  static bool get enabled => panelBuilder != null;

  /// Email akun admin tunggal — sumber kebenaran yang sama dengan guard
  /// RPC (coalesce(auth.email()) = email ini).
  static const String adminEmail = 'zunixe@gmail.com';

  /// User sesi aktif adalah admin sungguhan? Anon/guest & user biasa =
  /// false → seluruh UI admin (panel, toggle) disembunyikan walau di
  /// build admin.
  static bool isRealAdmin(String? email) => email == adminEmail;
}
