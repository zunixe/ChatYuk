import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings_admin.dart';
import '../providers/admin_provider.dart';
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
      children: [
        const _InfoCard(),
        const SizedBox(height: 12),
        const _ScreenshotToggle(),
        const SizedBox(height: 10),
        const _WatermarkToggle(),
        const SizedBox(height: 10),
        const _InvisibleToggle(),
        const SizedBox(height: 10),
        const _CallAllToggle(),
        const SizedBox(height: 10),
        const _RequireRegistrationToggle(),
        const SizedBox(height: 10),
        _ReengageToggle(),
        const SizedBox(height: 10),
        const _ExcludedDevicesTile(),
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

/// Toggle notifikasi pengingat harian (re-engagement): push ke user yang
/// offline 1-8 hari, tiap 19:00 WIB, berhenti setelah 7 hari. Server-side
/// (pg_cron + FCM); toggle ini hanya menulis app_settings.reengage_enabled.
class _ReengageToggle extends StatelessWidget {
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
            child: Icon(Icons.notifications_active_outlined,
                color: Colors.deepOrange, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.labelReengageNotif,
                  style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w500),
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
/// Exclude perangkat (install_id): perangkat yang di-exclude tidak dihitung
/// di ringkasan (users/aktif/anon) & disembunyikan dari tab Perangkat.
/// Fitur admin-only — dikelola dari Pengaturan Global.
class _ExcludedDevicesTile extends StatelessWidget {
  const _ExcludedDevicesTile();

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
              color: AppTheme.danger.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.phonelink_erase_rounded,
              color: AppTheme.danger,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.adminExcludeTitle,
                  style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  s.adminExcludeSubtitle,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 2),
                Text(
                  s.adminExcludeCount
                      .replaceFirst('%d', '${auth.excludedDevices.length}'),
                  style: AppText.caption.copyWith(
                    color: auth.excludedDevices.isEmpty
                        ? AppTheme.textSecondary
                        : AppTheme.danger,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: AppTheme.primary,
            tooltip: s.adminExcludeTitle,
            onPressed: () => _showExcludedSheet(context),
          ),
        ],
      ),
    );
  }

  void _showExcludedSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _ExcludedDevicesSheet(),
    );
  }
}

/// Bottom sheet kelola daftar install_id ter-exclude: lihat, tambah manual,
/// hapus per item. Simpan via AdminProvider.setExcludedDevices (RPC).
class _ExcludedDevicesSheet extends StatefulWidget {
  const _ExcludedDevicesSheet();

  @override
  State<_ExcludedDevicesSheet> createState() => _ExcludedDevicesSheetState();
}

class _ExcludedDevicesSheetState extends State<_ExcludedDevicesSheet> {
  late List<String> _ids;
  final _inputCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ids = List.of(context.read<AuthProvider>().excludedDevices);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  void _add() {
    final s = context.read<LocaleProvider>().s;
    final id = _inputCtrl.text.trim();
    if (id.isEmpty) {
      setState(() => _error = s.adminExcludeEmptyId);
      return;
    }
    if (_ids.contains(id)) {
      _inputCtrl.clear();
      setState(() => _error = null);
      return;
    }
    setState(() {
      _ids.add(id);
      _error = null;
      _inputCtrl.clear();
    });
  }

  void _remove(String id) {
    setState(() {
      _ids.remove(id);
      _error = null;
    });
  }

  Future<void> _save() async {
    final s = context.read<LocaleProvider>().s;
    setState(() => _saving = true);
    final ok = await context.read<AuthProvider>().setExcludedDevices(_ids);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? s.adminExcludeSaved : s.adminExcludeSaveFailed),
        backgroundColor: ok ? AppTheme.online : AppTheme.danger,
      ),
    );
    if (ok) {
      // Device yang dihapus dari exclude harus LANGSUNG muncul lagi di tab
      // Perangkat & ringkasan — refresh tanpa nunggu polling 15 detik.
      // Server sudah hapus cache stats; client cukup fetch ulang + buang
      // cache detail 60 detik supaya daftar user juga segar.
      try {
        final admin = context.read<AdminProvider>();
        admin.invalidateStatsDetail();
        unawaited(admin.refreshStats());
        unawaited(admin.fetchDevices());
      } catch (_) {}
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.adminExcludeAddTitle,
                        style: AppText.title,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  s.adminExcludeSubtitle,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _inputCtrl,
                        style: AppText.body,
                        decoration: InputDecoration(
                          hintText: s.adminExcludeAddHint,
                          isDense: true,
                        ),
                        onSubmitted: (_) => _add(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _add,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(s.adminExcludeAdd),
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _error!,
                      style: AppText.caption.copyWith(color: AppTheme.danger),
                    ),
                  ),
                ),
              Expanded(
                child: _ids.isEmpty
                    ? Center(
                        child: Text(
                          s.adminExcludeNone,
                          style: AppText.bodySmall.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                        itemCount: _ids.length,
                        itemBuilder: (_, i) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppTheme.bgScreen,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _ids[i],
                                    style: AppText.bodySmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  color: AppTheme.danger,
                                  tooltip: s.adminExcludeRemove,
                                  onPressed: () => _remove(_ids[i]),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(s.btnSave),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
