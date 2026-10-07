import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import '../../../config/theme.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/riverpod/locale_provider.dart';
import '../../../core/admin_err.dart';
import '../../../utils.dart' show formatRelativeTime;
import '../../../providers/riverpod/admin_provider.dart';

/// Konfigurasi popup update aplikasi (app_settings). Admin mengisi versi
/// terbaru/minimum + catatan; klien menampilkan popup saat masuk app.
class UpdateConfigTile extends ConsumerStatefulWidget {
  const UpdateConfigTile({super.key});

  @override
  ConsumerState<UpdateConfigTile> createState() => _UpdateConfigTileState();
}

class _UpdateConfigTileState extends ConsumerState<UpdateConfigTile> {
  final _latestCtrl = TextEditingController();
  final _minCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _enabled = false;
  bool _loading = true;
  bool _busy = false;
  DateTime? _lastPushAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _latestCtrl.dispose();
    _minCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final cfg = await ProviderScope.containerOf(context, listen: false).read(adminProvider).getUpdateConfig();
    final lastPush = await ProviderScope.containerOf(context, listen: false).read(adminProvider).getUpdatePushAt();
    if (!mounted) return;
    setState(() {
      _enabled = cfg?['update_enabled'] == true;
      _latestCtrl.text = '${cfg?['latest_version'] ?? ''}';
      _minCtrl.text = '${cfg?['min_version'] ?? ''}';
      _notesCtrl.text = '${cfg?['update_notes'] ?? ''}';
      _lastPushAt = lastPush;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (guardOfflineCtx(context, ProviderScope.containerOf(context, listen: false).read(localeProvider).s.adminNeedsConnection, (m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))))) return;
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    setState(() => _busy = true);
    try {
      await ProviderScope.containerOf(context, listen: false).read(adminProvider).saveUpdateConfig(
            enabled: _enabled,
            latestVersion: _latestCtrl.text,
            minVersion: _minCtrl.text,
            notes: _notesCtrl.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.adminUpdateSaved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.adminSaveFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Push popup update manual: konfirmasi → RPC admin_push_update → refresh
  /// label waktu. Popup tampil di app user saat mereka membuka app.
  Future<void> _push() async {
    final s = ProviderScope.containerOf(context, listen: false).read(localeProvider).s;
    if (guardOfflineCtx(
      context,
      s.adminNeedsConnection,
      (m) =>
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))),
    )) {
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(s.adminUpdatePushConfirmTitle),
        content: Text(s.adminUpdatePushConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(s.adminUpdatePushBtn),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ProviderScope.containerOf(context, listen: false).read(adminProvider).pushUpdate();
      final at = await ProviderScope.containerOf(context, listen: false).read(adminProvider).getUpdatePushAt();
      if (!mounted) return;
      setState(() => _lastPushAt = at ?? DateTime.now());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.adminUpdatePushDone)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.adminSaveFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.system_update_alt_rounded,
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
                      s.adminUpdateTitle,
                      style: AppText.bodyStrong.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      s.adminUpdateDesc,
                      style: AppText.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _enabled,
                onChanged: _loading
                    ? null
                    : (v) => setState(() => _enabled = v),
                activeThumbColor: AppTheme.primary,
              ),
            ],
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            const SizedBox(height: 12),
            TextField(
              controller: _latestCtrl,
              decoration: InputDecoration(
                labelText: s.adminUpdateLatest,
                isDense: true,
              ),
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _minCtrl,
              decoration: InputDecoration(
                labelText: s.adminUpdateMin,
                helperText: s.adminUpdateMinHint,
                isDense: true,
              ),
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notesCtrl,
              decoration: InputDecoration(
                labelText: s.adminUpdateNotes,
                isDense: true,
              ),
              maxLines: 3,
              minLines: 2,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || _loading ? null : _push,
                    icon: const Icon(Icons.campaign_rounded, size: 18),
                    label: Text(
                      s.adminUpdatePushBtn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(s.btnSave),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              s.adminUpdatePushDesc,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              _lastPushAt == null
                  ? '${s.adminUpdatePushLastAt}: ${s.adminUpdatePushNever}'
                  : '${s.adminUpdatePushLastAt}: ${formatRelativeTime(_lastPushAt!, isId: s.isId)}',
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
