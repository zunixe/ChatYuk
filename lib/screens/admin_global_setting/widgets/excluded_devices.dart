import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../core/admin_err.dart';

/// Exclude perangkat (install_id): perangkat yang di-exclude tidak dihitung
/// di ringkasan (users/aktif/anon) & disembunyikan dari tab Perangkat.
/// Fitur admin-only — dikelola dari Pengaturan Global.
class ExcludedDevicesTile extends StatelessWidget {
  const ExcludedDevicesTile({super.key});

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
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
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
                  s.adminExcludeCount.replaceFirst(
                    '%d',
                    '${auth.excludedDevices.length}',
                  ),
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
      builder: (_) => const ExcludedDevicesSheet(),
    );
  }
}

/// Bottom sheet kelola daftar install_id ter-exclude: lihat, tambah manual,
/// hapus per item. Simpan via AdminProvider.setExcludedDevices (RPC).
class ExcludedDevicesSheet extends StatefulWidget {
  const ExcludedDevicesSheet({super.key});

  @override
  State<ExcludedDevicesSheet> createState() => _ExcludedDevicesSheetState();
}

class _ExcludedDevicesSheetState extends State<ExcludedDevicesSheet> {
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
    if (guardOfflineCtx(context, context.read<LocaleProvider>().s.adminNeedsConnection, (m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))))) return;
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
        unawaited(admin.fetchHiddenUids());
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
                      child: Text(s.adminExcludeAddTitle, style: AppText.title),
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
                              horizontal: 12,
                              vertical: 8,
                            ),
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
