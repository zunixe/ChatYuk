import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/riverpod/auth_provider.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../widgets/toggle_tile.dart';
import '../../../providers/riverpod/admin_provider.dart';

/// Kartu pembungkus standar untuk baris pengaturan admin.
class SettingCard extends ConsumerWidget {
  final Widget child;
  const SettingCard({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

class InfoCard extends ConsumerWidget {
  const InfoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
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

class ScreenshotToggle extends ConsumerWidget {
  const ScreenshotToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final value = ref.watch(authProvider.select((a) => a.screenshotEnabled));
    return ToggleTile(
      icon: Icons.screenshot_monitor,
      color: AppTheme.online,
      title: s.labelScreenshotAllow,
      desc: s.descScreenshotAdmin,
      value: value,
      onChanged: (v) => ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).setScreenshotEnabled(v),
    );
  }
}

class WatermarkToggle extends ConsumerWidget {
  const WatermarkToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final value = ref.watch(authProvider.select((a) => a.watermarkEnabled));
    return ToggleTile(
      icon: Icons.fingerprint,
      color: AppTheme.primary,
      title: s.labelWatermarkAdmin,
      desc: s.descWatermarkAdmin,
      value: value,
      onChanged: (v) => ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).setWatermarkEnabled(v),
    );
  }
}

class InvisibleToggle extends ConsumerWidget {
  const InvisibleToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final value = ref.watch(authProvider.select((a) => a.invisibleEnabled));
    return ToggleTile(
      icon: Icons.visibility_off_outlined,
      color: AppTheme.accent,
      title: s.labelInvisibleAdmin,
      desc: s.descInvisibleAdmin,
      value: value,
      onChanged: (v) => ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).setInvisibleEnabled(v),
    );
  }
}

class CallToggle extends ConsumerWidget {
  const CallToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final enabled = ref.watch(
      authProvider.select((a) => a.callAllEnabled && a.callAnonEnabled),
    );
    return ToggleTile(
      icon: Icons.phone_in_talk_rounded,
      color: Colors.green,
      title: s.adminCallTitle,
      desc: s.adminCallDesc,
      value: enabled,
      onChanged: (v) => ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).setCallEnabled(v),
    );
  }
}

class RequireRegistrationToggle extends ConsumerWidget {
  const RequireRegistrationToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final value = ref.watch(authProvider.select((a) => a.requireRegistration));
    return ToggleTile(
      icon: Icons.how_to_reg_outlined,
      color: Colors.deepPurple,
      title: s.labelRequireRegistration,
      desc: s.descRequireRegistration,
      value: value,
      onChanged: (v) =>
          ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).setRequireRegistration(v),
    );
  }
}

/// Toggle notifikasi pengingat harian (re-engagement): push ke user yang
/// offline 1-8 hari, tiap 19:00 WIB, berhenti setelah 7 hari. Server-side
/// (pg_cron + FCM); toggle ini hanya menulis app_settings.reengage_enabled.
class ReengageToggle extends ConsumerWidget {
  const ReengageToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(localeProvider).s;
    final value = ref.watch(authProvider.select((a) => a.reengageEnabled));
    return ToggleTile(
      icon: Icons.notifications_active_outlined,
      color: Colors.deepOrange,
      title: s.labelReengageNotif,
      desc: s.descReengageNotif,
      value: value,
      onChanged: (v) => ProviderScope.containerOf(context, listen: false).read(authProvider.notifier).setReengageEnabled(v),
    );
  }
}

/// Hapus data admin yang tersimpan di perangkat (cache offline).
/// Data admin memuat PII user (email/IP/device) — berguna bila HP bergantian
/// dipakai. Cache ini juga yang membuat panel tetap tampil saat offline.
class ClearAdminCacheTile extends ConsumerWidget {
  const ClearAdminCacheTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
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
          final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
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
