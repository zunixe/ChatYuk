import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../core/admin_gate.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../config/strings_admin.dart';

/// Section pengaturan admin di halaman Profil — HANYA di-import oleh
/// entry admin (via admin_wiring.dart). Build rilis tidak pernah
/// menyentuh file ini.
///
/// [adminSettingsHeader] = tile buka Admin Panel (+divider), ditaruh
/// sebelum baris Notifikasi. [adminSettingsTail] = toggle screenshot/
/// watermark/invisible (+divider penutup), sesudah baris Notifikasi.

List<Widget> adminSettingsHeader(BuildContext context) {
  if (!AdminGate.enabled) return const [];
  // Hanya admin sungguhan (zunixe) yang melihat UI admin. Login anon/user
  // biasa di build admin = tampilan user normal.
  final auth = context.read<AuthProvider>();
  final isDummy = auth.dummySessionActive;
  if (isDummy || !auth.isRealAdmin) return const [];
  return const [_AdminPanelTile(), _AdminDivider()];
}

List<Widget> adminSettingsTail(BuildContext context) {
  // Semua toggle admin (screenshot, watermark, invisible, call-all,
  // registrasi wajib) dipindah ke tab "Pengaturan Global" di admin panel.
  if (!AdminGate.enabled) return const [];
  final auth = context.read<AuthProvider>();
  final isDummy = auth.dummySessionActive;
  if (isDummy || !auth.isRealAdmin) return const [];
  return const [];
}

class _AdminDivider extends StatelessWidget {
  const _AdminDivider();

  @override
  Widget build(BuildContext context) => const Divider(height: 1, indent: 52);
}

/// Tile buka Admin Panel — navigasi lewat AdminGate.panelBuilder supaya
/// file ini tidak perlu meng-import admin_panel_screen langsung.
class _AdminPanelTile extends StatelessWidget {
  const _AdminPanelTile();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final builder = AdminGate.panelBuilder;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: InkWell(
        onTap: builder == null
            ? null
            : () =>
                  Navigator.push(context, MaterialPageRoute(builder: builder)),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.admin_panel_settings,
                color: AppTheme.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                s.adminPanel,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}


/// Banner sesi dummy — tampil di atas body Profil saat admin sedang
/// memakai akun dummy. Tombolnya menjalankan [backToAdminFlow].
Widget? dummySessionBanner(BuildContext context, String? nickname) {
  final s = context.watch<LocaleProvider>().s;
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          AppTheme.accent.withValues(alpha: 0.18),
          AppTheme.accent.withValues(alpha: 0.06),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.accent.withValues(alpha: 0.45)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.theater_comedy_rounded,
                color: AppTheme.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.dummyBannerTitle,
                    style: AppText.bodyStrong.copyWith(color: AppTheme.accent),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.dummyBannerSubtitle.replaceFirst('%s', nickname ?? '—'),
                    style: AppText.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => backToAdminFlow(context),
            icon: const Icon(
              Icons.admin_panel_settings_rounded,
              size: 18,
              color: Colors.white,
            ),
            label: Text(
              s.dummyBackToAdmin,
              style: AppText.label.copyWith(
                letterSpacing: 0,
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Dialog konfirmasi → kembali ke akun admin → snackbar hasil.
Future<void> backToAdminFlow(BuildContext context) async {
  final s = context.read<LocaleProvider>().s;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(s.dummyBackConfirmTitle),
      content: Text(s.dummyBackConfirmBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            s.btnCancel,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            s.dummyBackToAdmin,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (!context.mounted) return;
  final ok = await context.read<AuthProvider>().backToAdmin();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(content: Text(ok ? s.dummyBackDone : s.dummyBackFailed)),
    );
}
