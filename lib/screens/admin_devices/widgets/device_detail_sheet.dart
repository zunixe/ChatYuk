import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../core/admin_err.dart';
import '../../../utils.dart';

/// Bottom sheet detail satu device → daftar user yang pernah login.
class DeviceDetailSheet extends StatelessWidget {
  final Map<String, dynamic> group;
  final S s;
  final void Function(Map<String, dynamic> user) onOpenUser;
  const DeviceDetailSheet({
    super.key,
    required this.group,
    required this.s,
    required this.onOpenUser,
  });

  @override
  Widget build(BuildContext context) {
    final brand = '${group['brand'] ?? ''}';
    final model = '${group['model'] ?? ''}';
    final osName = '${group['os_name'] ?? ''}';
    final osVersion = '${group['os_version'] ?? ''}';
    final appVer = '${group['app_version'] ?? ''}';
    final ip = '${group['ip_address'] ?? ''}';
    final installId = '${group['install_id'] ?? ''}';
    final lastSeen = group['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${group['last_seen_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';
    final users = (group['users'] as List<Map<String, dynamic>>? ?? const []);
    final deviceLabel = [
      if (brand.isNotEmpty) brand,
      if (model.isNotEmpty) model,
    ].join(' ').trim();
    final osLabel = [
      if (osName.isNotEmpty) osName,
      if (osVersion.isNotEmpty) osVersion,
    ].join(' ').trim();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.phone_android,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deviceLabel.isEmpty ? 'Unknown device' : deviceLabel,
                          style: AppText.title,
                        ),
                        if (osLabel.isNotEmpty)
                          Text(
                            osLabel,
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (appVer.isNotEmpty)
                    _kv(s.adminDeviceModel, deviceLabel),
                  if (osLabel.isNotEmpty) _kv(s.adminDeviceOs, osLabel),
                  if (appVer.isNotEmpty) _kv('App', 'v$appVer'),
                  if (ip.isNotEmpty) _kv(s.adminDeviceIp, ip),
                  _kv(s.adminDeviceInstallId, installId),
                  if (lastSeen.isNotEmpty)
                    _kv(s.adminDeviceLastSeen, lastSeen),
                  const SizedBox(height: 12),

                  // Exclude perangkat ini dari ringkasan & daftar perangkat.
                  OutlinedButton.icon(
                    onPressed: () => _excludeDevice(context, installId),
                    icon: const Icon(Icons.phonelink_erase_rounded, size: 18),
                    label: Text(s.adminExcludeDeviceAction),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.danger,
                      side: const BorderSide(color: AppTheme.danger),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      s.adminDeviceUsersUsed,
                      style: AppText.label.copyWith(color: AppTheme.primary),
                    ),
                  ),
                  if (users.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        s.adminDeviceNoUsers,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    for (final u in users) _userChip(u),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          Expanded(child: Text(v, style: AppText.bodySmall)),
        ],
      ),
    );
  }

  /// Exclude perangkat ini: RPC cascade menambahkan install_id SEKALIGUS
  /// semua uid yang pernah login di device ini (ke `excluded_uids`).
  /// Cascade wajib karena `install_id` bisa berubah untuk HP yang sama
  /// (Android ID ter-scope ke signing key) — tanpa itu device ter-exclude
  /// "muncul lagi" sebagai device baru.
  Future<void> _excludeDevice(BuildContext context, String installId) async {
    if (installId.isEmpty) return;
    final s = context.read<LocaleProvider>().s;
    // Aksi tulis: tidak boleh jalan saat offline (gagal separuh jalan).
    if (guardOfflineCtx(
      context,
      s.adminNeedsConnection,
      (m) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(m))),
    )) {
      return;
    }
    final auth = context.read<AuthProvider>();
    if (auth.excludedDevices.contains(installId)) return;
    final ok = await auth.excludeDeviceCascade(installId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? s.adminExcludeDeviceDone : s.adminExcludeSaveFailed,
        ),
        backgroundColor: ok ? AppTheme.online : AppTheme.danger,
      ),
    );
    if (ok) {
      // Tutup sheet + refresh daftar supaya item ter-exclude langsung hilang.
      Navigator.pop(context);
      context.read<AdminProvider>().invalidateStatsDetail();
      await context.read<AdminProvider>().fetchDevices();
    }
  }

  Widget _userChip(Map<String, dynamic> u) {
    final nick = '${u['nickname'] ?? '?'}';
    final registered = u['is_registered'] == true;
    final lastSeen = u['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${u['last_seen_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: AppTheme.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onOpenUser(u),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: (registered ? AppTheme.primary : AppTheme.accent)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    nick.isNotEmpty ? nick[0].toUpperCase() : '?',
                    style: AppText.bodyStrong.copyWith(
                      color: registered ? AppTheme.primary : AppTheme.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nick, style: AppText.bodyStrong),
                    Text(
                      [
                        registered ? s.adminDeviceRegistered : s.adminDeviceAnon,
                        if (lastSeen.isNotEmpty)
                          '${s.adminDeviceLastSeen}: $lastSeen',
                      ].join(' · '),
                      style: AppText.micro.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
