import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/admin_gate.dart';
import '../providers/admin_provider.dart';
import '../screens/admin_panel_screen.dart';
import 'dummy_session.dart';
import 'profile_sections.dart';

/// Pasang semua modul admin ke AdminGate. Dipanggil HANYA dari
/// lib/main_admin.dart — build rilis tidak pernah meng-import file ini.
void wireAdmin() {
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
