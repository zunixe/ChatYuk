import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings_admin.dart';
import '../config/supabase_config.dart';
import '../providers/admin_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../services/admin_service.dart';

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
        const _AiGlobalTile(),
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
/// AI Bot global: master switch semua balasan AI dummy + rate limit
/// (maks balasan per chat per jam & jeda minimal antar balasan).
class _AiGlobalTile extends StatefulWidget {
  const _AiGlobalTile();

  @override
  State<_AiGlobalTile> createState() => _AiGlobalTileState();
}

class _AiGlobalTileState extends State<_AiGlobalTile> {
  final AdminService _svc = AdminService(SupabaseConfig.client);
  bool _loading = true;
  bool _globalEnabled = true;
  int _maxReplies = 20;
  int _minInterval = 2;
  bool _guardEnabled = true;
  String _activeLabel = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st = await _svc.getAiSettings();
      List<Map<String, dynamic>> providers = const [];
      try {
        providers = await _svc.getAiProviders();
      } catch (_) {}
      if (!mounted) return;
      String activeLabel = '';
      for (final p in providers) {
        if (p['is_active'] == true) {
          activeLabel = '${p['label'] ?? p['id'] ?? ''}';
          break;
        }
      }
      setState(() {
        _globalEnabled = st['ai_global_enabled'] != false;
        _maxReplies = (st['ai_max_replies_per_hour'] as num?)?.toInt() ?? 20;
        _minInterval = (st['ai_min_interval_sec'] as num?)?.toInt() ?? 2;
        _guardEnabled = st['ai_guard_enabled'] != false;
        _activeLabel = activeLabel;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool v) async {
    setState(() => _globalEnabled = v);
    try {
      await _svc.setAiSettings(globalEnabled: v);
    } catch (_) {
      if (mounted) setState(() => _globalEnabled = !v);
    }
  }

  Future<void> _openAiBotSheet() async {
    final maxCtrl = TextEditingController(text: '$_maxReplies');
    final minCtrl = TextEditingController(text: '$_minInterval');
    bool guardTmp = _guardEnabled;
    final s = context.read<LocaleProvider>().s;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom:
                20 +
                MediaQuery.viewInsetsOf(ctx).bottom +
                MediaQuery.of(ctx).padding.bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.aiGlobalTitle,
                  style: AppText.title,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: maxCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppText.body,
                  decoration: InputDecoration(
                    labelText: s.aiGlobalMaxReplies,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: minCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: AppText.body,
                  decoration: InputDecoration(
                    labelText: s.aiGlobalMinInterval,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.aiGlobalGuardTitle, style: AppText.body),
                          Text(
                            s.aiGlobalGuardDesc,
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: guardTmp,
                      onChanged: (v) => setSheetState(() => guardTmp = v),
                      activeThumbColor: AppTheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () async {
                    final max =
                        int.tryParse(maxCtrl.text.trim()) ?? _maxReplies;
                    final min =
                        int.tryParse(minCtrl.text.trim()) ?? _minInterval;
                    try {
                      await _svc.setAiSettings(
                        maxReplies: max,
                        minInterval: min,
                        guardEnabled: guardTmp,
                      );
                      if (!mounted) return;
                      setState(() {
                        _maxReplies = max;
                        _minInterval = min;
                        _guardEnabled = guardTmp;
                      });
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx)
                          ..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(content: Text(s.aiGlobalSaved)),
                          );
                      }
                    } catch (_) {}
                  },
                  child: Text(s.btnSave),
                ),
                const SizedBox(height: 16),
                Text(
                  s.aiProviderListTitle,
                  style: AppText.bodyStrong,
                ),
                const _ProviderListSection(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    maxCtrl.dispose();
    minCtrl.dispose();
    // Refresh label provider aktif setelah sheet ditutup.
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
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
            child: const Icon(
              Icons.smart_toy_outlined,
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
                  s.aiGlobalTitle,
                  style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w500),
                ),
                Text(
                  s.aiGlobalDesc,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                ),
                if (!_loading)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${s.aiGlobalMaxReplies}: $_maxReplies · ${s.aiGlobalMinInterval}: $_minInterval · ${s.aiGlobalGuardTitle}: ${_guardEnabled ? 'ON' : 'OFF'}${_activeLabel.isNotEmpty ? ' · $_activeLabel' : ''}',
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.tune, size: 20),
            color: AppTheme.primary,
            tooltip: s.aiGlobalTitle,
            onPressed: _loading ? null : _openAiBotSheet,
          ),
          _loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Switch(
                  value: _globalEnabled,
                  onChanged: _toggle,
                  activeThumbColor: AppTheme.primary,
                ),
        ],
      ),
    );
  }
}

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

/// Daftar provider AI: tap = expand (model, base URL, API key),
/// radio = provider yang dipakai edge function. Bisa tambah baru.
class _ProviderListSection extends StatefulWidget {
  const _ProviderListSection();

  @override
  State<_ProviderListSection> createState() => _ProviderListSectionState();
}

class _ProviderListSectionState extends State<_ProviderListSection> {
  final AdminService _svc = AdminService(SupabaseConfig.client);
  bool _loading = true;
  bool _failed = false;
  List<Map<String, dynamic>> _items = const [];
  String? _expandedId;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await _svc.getAiProviders();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                s.aiProviderLoadFail,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: _reload,
              child: Text(s.btnRetry),
            ),
          ],
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in _items)
          _ProviderCard(
            key: ValueKey('prov-${p['id']}'),
            data: p,
            expanded: _expandedId == '${p['id']}',
            onToggleExpand: () {
              setState(() {
                _expandedId =
                    _expandedId == '${p['id']}' ? null : '${p['id']}';
              });
            },
            onChanged: _reload,
          ),
        if (_adding)
          _ProviderCard(
            key: const ValueKey('prov-new'),
            data: const {},
            expanded: true,
            isNew: true,
            onToggleExpand: () => setState(() => _adding = false),
            onChanged: () {
              setState(() => _adding = false);
              _reload();
            },
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _adding
                ? null
                : () => setState(() {
                      _adding = true;
                      _expandedId = null;
                    }),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(s.aiProviderAdd),
          ),
        ),
      ],
    );
  }
}

/// Satu kartu provider: radio + label + model; expand = edit 4 field.
class _ProviderCard extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool expanded;
  final bool isNew;
  final VoidCallback onToggleExpand;
  final VoidCallback onChanged;

  const _ProviderCard({
    super.key,
    required this.data,
    required this.expanded,
    this.isNew = false,
    required this.onToggleExpand,
    required this.onChanged,
  });

  @override
  State<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends State<_ProviderCard> {
  final AdminService _svc = AdminService(SupabaseConfig.client);
  late final TextEditingController _labelCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _baseCtrl;
  late final TextEditingController _keyCtrl;
  bool _busy = false;
  bool _activating = false;

  @override
  void initState() {
    super.initState();
    _labelCtrl = TextEditingController(text: '${widget.data['label'] ?? ''}');
    _modelCtrl = TextEditingController(
        text: '${widget.data['default_model'] ?? ''}');
    _baseCtrl = TextEditingController(text: '${widget.data['api_base'] ?? ''}');
    _keyCtrl = TextEditingController(text: '${widget.data['api_key'] ?? ''}');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _modelCtrl.dispose();
    _baseCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final s = context.read<LocaleProvider>().s;
    setState(() => _busy = true);
    try {
      await _svc.saveAiProvider(
        id: widget.isNew ? null : '${widget.data['id']}',
        label: _labelCtrl.text.trim().isEmpty
            ? null
            : _labelCtrl.text.trim(),
        apiBase: _baseCtrl.text.trim().isEmpty ? null : _baseCtrl.text.trim(),
        apiKey: _keyCtrl.text.trim().isEmpty ? null : _keyCtrl.text.trim(),
        defaultModel:
            _modelCtrl.text.trim().isEmpty ? null : _modelCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.aiProviderSaved)));
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.errGeneric)));
    }
  }

  Future<void> _activate() async {
    final s = context.read<LocaleProvider>().s;
    setState(() => _activating = true);
    try {
      await _svc.activateAiProvider('${widget.data['id']}');
      if (!mounted) return;
      setState(() => _activating = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.aiProviderActivated)));
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() => _activating = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.errGeneric)));
    }
  }

  Future<void> _delete() async {
    final s = context.read<LocaleProvider>().s;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.aiProviderDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              s.btnDelete,
              style: const TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _svc.deleteAiProvider('${widget.data['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.aiProviderDeleted)));
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(s.aiProviderDeleteActive)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final active = widget.data['is_active'] == true && !widget.isNew;
    final model = '${widget.data['default_model'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgScreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? AppTheme.primary
              : AppTheme.textSecondary.withValues(alpha: 0.25),
          width: active ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  widget.isNew
                      ? const Icon(
                          Icons.add_circle_outline_rounded,
                          color: AppTheme.primary,
                          size: 22,
                        )
                      : _activating
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: Padding(
                                padding: EdgeInsets.all(3),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Radio<bool>(
                              value: true,
                              groupValue: active ? true : null,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              onChanged: (_) {
                                if (!active) _activate();
                              },
                            ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isNew
                              ? s.aiProviderAdd
                              : '${widget.data['label'] ?? widget.data['id'] ?? ''}',
                          style: AppText.bodyStrong,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!widget.isNew && model.isNotEmpty)
                          Text(
                            model,
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  if (active)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        s.aiProviderActive,
                        style: AppText.label.copyWith(
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  Icon(
                    widget.expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: AppTheme.textSecondary,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          if (widget.expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _labelCtrl,
                    style: AppText.body,
                    decoration: InputDecoration(
                      labelText: s.aiProviderLabel,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _modelCtrl,
                    style: AppText.body,
                    decoration: InputDecoration(
                      labelText: s.aiGlobalModel,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _baseCtrl,
                    style: AppText.body,
                    decoration: InputDecoration(
                      labelText: s.aiGlobalBaseUrl,
                      helperText: s.aiGlobalProviderHint,
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _keyCtrl,
                    obscureText: true,
                    style: AppText.body,
                    decoration: InputDecoration(
                      labelText: s.aiGlobalApiKey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (!widget.isNew)
                        TextButton.icon(
                          onPressed: _busy ? null : _delete,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                            color: AppTheme.danger,
                          ),
                          label: Text(
                            s.btnDelete,
                            style: const TextStyle(color: AppTheme.danger),
                          ),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _busy ? null : _save,
                        child: Text(
                          widget.isNew ? s.aiProviderAdd : s.aiProviderSave,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
