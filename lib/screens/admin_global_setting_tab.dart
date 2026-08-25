import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings_admin.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
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
      children: const [
        _InfoCard(),
        SizedBox(height: 12),
        _ScreenshotToggle(),
        SizedBox(height: 10),
        _WatermarkToggle(),
        SizedBox(height: 10),
        _InvisibleToggle(),
        SizedBox(height: 10),
        _CallAllToggle(),
        SizedBox(height: 10),
        _RequireRegistrationToggle(),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard();

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.admin_panel_settings_outlined,
              size: 20, color: AppTheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.descScreenshotAdminBuild,
              style: AppText.bodySmall.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScreenshotToggle extends StatelessWidget {
  const _ScreenshotToggle();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final auth = context.watch<AuthProvider>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.online.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.screenshot_monitor,
              color: AppTheme.online,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.labelScreenshotAllow,
                  style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  s.descScreenshotAdmin,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          Switch(
            value: auth.screenshotEnabled,
            onChanged: (v) =>
                context.read<AuthProvider>().setScreenshotEnabled(v),
            activeThumbColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

class _WatermarkToggle extends StatelessWidget {
  const _WatermarkToggle();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final auth = context.watch<AuthProvider>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.fingerprint,
              color: AppTheme.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.labelWatermarkAdmin,
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  s.descWatermarkAdmin,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          Switch(
            value: auth.watermarkEnabled,
            onChanged: (v) =>
                context.read<AuthProvider>().setWatermarkEnabled(v),
            activeThumbColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

class _InvisibleToggle extends StatelessWidget {
  const _InvisibleToggle();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final auth = context.watch<AuthProvider>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.visibility_off_outlined,
              color: AppTheme.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.labelInvisibleAdmin,
                  style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  s.descInvisibleAdmin,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          Switch(
            value: auth.invisibleEnabled,
            onChanged: (v) =>
                context.read<AuthProvider>().setInvisibleEnabled(v),
            activeThumbColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

class _CallAllToggle extends StatelessWidget {
  const _CallAllToggle();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final auth = context.watch<AuthProvider>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.phone_in_talk_rounded,
                color: Colors.green, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.adminCallAllTitle,
                  style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  s.adminCallAllDesc,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          Switch(
            value: auth.callAllEnabled,
            onChanged: (v) =>
                context.read<AuthProvider>().setCallAllEnabled(v),
            activeThumbColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

class _RequireRegistrationToggle extends StatelessWidget {
  const _RequireRegistrationToggle();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final auth = context.watch<AuthProvider>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.how_to_reg_outlined,
                color: Colors.deepPurple, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.labelRequireRegistration,
                  style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  s.descRequireRegistration,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          Switch(
            value: auth.requireRegistration,
            onChanged: (v) =>
                context.read<AuthProvider>().setRequireRegistration(v),
            activeThumbColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}