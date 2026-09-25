import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/locale_provider.dart';

/// Bypass privasi: ON = akun admin melihat semua field profil user
/// (foto/status/last_seen/about/story) tanpa filter visibility.
/// Server tetap menegakkan: user biasa tidak terdampak (cek email admin).
class PrivacyBypassTile extends StatefulWidget {
  const PrivacyBypassTile({super.key});

  @override
  State<PrivacyBypassTile> createState() => _PrivacyBypassTileState();
}

class _PrivacyBypassTileState extends State<PrivacyBypassTile> {
  bool _loading = true;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final st = await context.read<AdminProvider>().getPointSettings();
      if (!mounted) return;
      setState(() {
        _enabled = st['privacy_bypass_enabled'] == true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(bool v) async {
    setState(() => _enabled = v);
    try {
      await context.read<AdminProvider>().setPrivacyBypass(v);
    } catch (_) {
      if (mounted) setState(() => _enabled = !v);
    }
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
              color: AppTheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.visibility_outlined,
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
                  s.privacyBypassTitle,
                  style: AppText.bodyStrong.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  s.privacyBypassDesc,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          _loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Switch(
                  value: _enabled,
                  onChanged: _toggle,
                  activeThumbColor: AppTheme.primary,
                ),
        ],
      ),
    );
  }
}
