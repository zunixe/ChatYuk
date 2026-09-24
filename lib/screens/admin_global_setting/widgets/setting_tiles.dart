import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/locale_provider.dart';

/// Kartu pembungkus standar untuk baris pengaturan admin.
class SettingCard extends StatelessWidget {
  final Widget child;
  const SettingCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: child,
      ),
    );
  }
}

class InfoCard extends StatelessWidget {
  const InfoCard({super.key});

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
          Icon(
            Icons.admin_panel_settings_outlined,
            size: 20,
            color: AppTheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.descScreenshotAdminBuild,
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class ScreenshotToggle extends StatelessWidget {
  const ScreenshotToggle({super.key});

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
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
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

class WatermarkToggle extends StatelessWidget {
  const WatermarkToggle({super.key});

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

class InvisibleToggle extends StatelessWidget {
  const InvisibleToggle({super.key});

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
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
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

class CallToggle extends StatelessWidget {
  const CallToggle({super.key});

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
            child: Icon(
              Icons.phone_in_talk_rounded,
              color: Colors.green,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.adminCallTitle,
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  s.adminCallDesc,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          Switch(
            value: auth.callAllEnabled && auth.callAnonEnabled,
            onChanged: (v) => context.read<AuthProvider>().setCallEnabled(v),
            activeThumbColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

class RequireRegistrationToggle extends StatelessWidget {
  const RequireRegistrationToggle({super.key});
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
            child: Icon(
              Icons.how_to_reg_outlined,
              color: Colors.deepPurple,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.labelRequireRegistration,
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
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

/// Toggle notifikasi pengingat harian (re-engagement): push ke user yang
/// offline 1-8 hari, tiap 19:00 WIB, berhenti setelah 7 hari. Server-side
/// (pg_cron + FCM); toggle ini hanya menulis app_settings.reengage_enabled.
class ReengageToggle extends StatelessWidget {
  const ReengageToggle({super.key});
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
              color: Colors.deepOrange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_active_outlined,
              color: Colors.deepOrange,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.labelReengageNotif,
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  s.descReengageNotif,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          Switch(
            value: auth.reengageEnabled,
            onChanged: (v) =>
                context.read<AuthProvider>().setReengageEnabled(v),
            activeThumbColor: AppTheme.primary,
          ),
        ],
      ),
    );
  }
}

/// Hapus data admin yang tersimpan di perangkat (cache offline).
/// Data admin memuat PII user (email/IP/device) — berguna bila HP bergantian
/// dipakai. Cache ini juga yang membuat panel tetap tampil saat offline.
class ClearAdminCacheTile extends StatelessWidget {
  const ClearAdminCacheTile({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.read<LocaleProvider>().s;
    return SettingCard(
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.danger.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.cleaning_services_outlined,
            size: 18,
            color: AppTheme.danger,
          ),
        ),
        title: Text(s.adminClearCache, style: AppText.bodyStrong),
        subtitle: Text(
          s.adminClearCacheDesc,
          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final admin = context.read<AdminProvider>();
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.bgCard,
              title: Text(s.adminClearCache, style: AppText.title),
              content: Text(s.adminClearCacheConfirm, style: AppText.body),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(s.btnCancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: Text(
                    s.adminClearCache,
                    style: TextStyle(color: AppTheme.danger),
                  ),
                ),
              ],
            ),
          );
          if (ok != true) return;
          await admin.clearAdminCache();
          messenger.showSnackBar(
            SnackBar(content: Text(s.adminClearCacheDone)),
          );
        },
      ),
    );
  }
}
