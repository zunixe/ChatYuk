import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/admin_gate.dart';
import '../services/auth_service.dart';
import '../providers/admin_provider.dart';
import '../screens/admin_panel_screen.dart';
import 'dummy_session.dart';
import 'profile_sections.dart';

/// Pasang semua modul admin ke AdminGate. Dipanggil HANYA dari
/// lib/main_admin.dart — build rilis tidak pernah meng-import file ini.
void wireAdmin() {
  // Google Sign-In build admin: Android client-nya di project chatyuk-7c9e4
  // → wajib pakai Web client dari project yang SAMA (aturan Google; lihat
  // doc di AuthService.googleWebClientIdDefault).
  AuthService.googleWebClientIdOverride =
      '599111437536-hg56bq0nc2m6kig6hg41lmrbtfel5n2c.apps.googleusercontent.com';
  AdminGate.panelBuilder = (_) => const AdminPanelScreen();
  AdminGate.becomeDummyImpl = DummySession.becomeDummy;
  AdminGate.backToAdminImpl = DummySession.backToAdmin;
  AdminGate.restoreDummySession = DummySession.restoreIfNeeded;
  AdminGate.hasStoredDummyTokens = DummySession.hasStoredTokens;
  AdminGate.onSignOut = DummySession.clearStored;
  AdminGate.dummySessionBanner = dummySessionBanner;
  AdminGate.extraProviders = <SingleChildWidget>[
    ChangeNotifierProvider(create: (_) => AdminProvider()),
  ];
  AdminGate.profileSettingsHeader = adminSettingsHeader;
  AdminGate.profileSettingsTail = adminSettingsTail;
}
