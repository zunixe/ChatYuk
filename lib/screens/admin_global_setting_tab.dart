import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'admin_global_setting/widgets/setting_tiles.dart';
import 'admin_global_setting/widgets/ai_global_tile.dart';
import 'admin_global_setting/widgets/app_font_settings.dart';
import 'admin_global_setting/widgets/excluded_devices.dart';
import 'admin_global_setting/widgets/update_config_tile.dart';
import '../providers/theme_provider.dart';

/// Admin panel — tab "Global Setting".
/// Berisi semua toggle pengaturan global aplikasi (screenshot, watermark,
/// invisible, tombol call, registrasi wajib).
///
/// Catatan screenshot: setting "izinkan screenshot aplikasi" HANYA berlaku
/// untuk ChatYuk user. Build admin selalu bisa screenshot (untuk kebutuhan
/// dokumentasi/dukungan admin).
class AdminGlobalSettingTab extends StatelessWidget {
  const AdminGlobalSettingTab({super.key});

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 24,
      ),
      children: [
        const InfoCard(),
        const SizedBox(height: 12),
        const ScreenshotToggle(),
        const SizedBox(height: 10),
        const WatermarkToggle(),
        const SizedBox(height: 10),
        const InvisibleToggle(),
        const SizedBox(height: 10),
        const CallToggle(),
        const SizedBox(height: 10),
        const RequireRegistrationToggle(),
        const SizedBox(height: 10),
        const ReengageToggle(),
        const SizedBox(height: 10),
        const AiGlobalTile(),
        const SizedBox(height: 10),
        const AppFontTile(),
        const SizedBox(height: 10),
        const ExcludedDevicesTile(),
        const SizedBox(height: 10),
        const UpdateConfigTile(),
        const SizedBox(height: 10),
        const ClearAdminCacheTile(),
      ],
    );
  }
}




