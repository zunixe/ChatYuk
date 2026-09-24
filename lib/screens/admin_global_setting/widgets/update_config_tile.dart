import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../core/admin_err.dart';

/// Konfigurasi popup update aplikasi (app_settings). Admin mengisi versi
/// terbaru/minimum + catatan; klien menampilkan popup saat masuk app.
class UpdateConfigTile extends StatefulWidget {
  const UpdateConfigTile({super.key});

  @override
  State<UpdateConfigTile> createState() => _UpdateConfigTileState();
}

class _UpdateConfigTileState extends State<UpdateConfigTile> {
  final _latestCtrl = TextEditingController();
  final _minCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _enabled = false;
  bool _loading = true;
  bool _busy = false;

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
    final cfg = await context.read<AdminProvider>().getUpdateConfig();
    if (!mounted) return;
    setState(() {
      _enabled = cfg?['update_enabled'] == true;
      _latestCtrl.text = '${cfg?['latest_version'] ?? ''}';
      _minCtrl.text = '${cfg?['min_version'] ?? ''}';
      _notesCtrl.text = '${cfg?['update_notes'] ?? ''}';
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (guardOfflineCtx(context, context.read<LocaleProvider>().s.adminNeedsConnection, (m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))))) return;
    final s = context.read<LocaleProvider>().s;
    setState(() => _busy = true);
    try {
      await context.read<AdminProvider>().saveUpdateConfig(
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

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
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
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(s.btnSave),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
