import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import 'panel_card.dart';

/// Daftar user yang dilaporkan + jumlah laporan.
class ReportedUsersCard extends StatelessWidget {
  final Map<String, dynamic>? stats;
  final S s;
  const ReportedUsersCard({super.key, required this.stats, required this.s});

  @override
  Widget build(BuildContext context) {
    final reports = (stats?['reported_users'] as List?) ?? [];
    return PanelCard(s.adminReports, Icons.flag_outlined, Colors.orange, [
      if (reports.isEmpty)
        Text(
          s.adminNoReports,
          style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
        ),
      for (var i = 0; i < reports.length && i < 8; i++)
        _reportRow(reports[i]),
    ]);
  }

  Widget _reportRow(dynamic raw) {
    final r = (raw as Map?) ?? const {};
    final reportedId = r['reported_id']?.toString() ?? '';
    final nickname = (r['reported_nickname'] ?? '').toString();
    final registered = r['reported_registered'] == true;
    final count = r['report_count'];
    // Label terlapor: nickname kalau ada, kalau tidak uid terpotong.
    final who = nickname.isNotEmpty
        ? nickname
        : (reportedId.length >= 8 ? '${reportedId.substring(0, 8)}…' : '?');

    final reporters = (r['reporters'] as List?) ?? const [];
    final reporterNames = reporters
        .map((e) {
          final m = (e as Map?) ?? const {};
          final n = (m['nickname'] ?? '').toString();
          final id = m['id']?.toString() ?? '';
          if (n.isNotEmpty) return n;
          return id.length >= 8 ? '${id.substring(0, 8)}…' : '?';
        })
        .where((e) => e.isNotEmpty)
        .toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                registered ? Icons.person : Icons.person_outline,
                size: 16,
                color: AppTheme.danger,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodyStrong.copyWith(color: AppTheme.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${count}x',
                  style: AppText.caption.copyWith(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Baris "Dilaporkan oleh: …" supaya jelas pelapor ≠ terlapor.
          Text(
            reporterNames.isEmpty
                ? '${s.adminReportedBy}: —'
                : '${s.adminReportedBy}: ${reporterNames.join(', ')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.micro.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Paksa logout satu user berdasarkan uid.
class ForceLogoutCard extends StatelessWidget {
  final S s;
  final TextEditingController logoutCtrl;
  final void Function(String msg) onToast;
  const ForceLogoutCard({
    super.key,
    required this.s,
    required this.logoutCtrl,
    required this.onToast,
  });

  @override
  Widget build(BuildContext context) {
    return PanelCard(s.adminForceLogout, Icons.logout, Colors.orange, [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: logoutCtrl,
              style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: s.labelUserId,
                isDense: true,
                filled: true,
                fillColor: AppTheme.bgInput,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: () async {
              final uid = logoutCtrl.text.trim();
              if (uid.isEmpty) return;
              try {
                // Await — forceLogout melempar saat gagal; tanpa await
                // error jadi unhandled dan toast "sukses" tampil keliru.
                await context.read<AdminProvider>().forceLogout(uid);
                onToast(s.adminForceLogoutDone(uid.substring(0, 8)));
                logoutCtrl.clear();
              } catch (e) {
                onToast('${s.errGeneric}$e');
              }
            },
            icon: const Icon(Icons.logout, size: 16, color: Colors.orange),
            label: Text(
              s.adminLogout,
              style: const TextStyle(color: Colors.orange),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
            ),
          ),
        ],
      ),
    ]);
  }
}

/// Zona berbahaya: reset semua poin (konfirmasi dialog dulu).
class DangerZoneCard extends StatelessWidget {
  final AdminProvider admin;
  final S s;
  final void Function(String msg) onToast;
  const DangerZoneCard({
    super.key,
    required this.admin,
    required this.s,
    required this.onToast,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: AppTheme.danger),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.adminDangerZone,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  s.adminResetAllPoints,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppTheme.bgCard,
                  title: Text(
                    s.adminResetAllTitle,
                    style: TextStyle(color: AppTheme.textPrimary),
                  ),
                  content: Text(
                    s.adminResetAllBody,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(s.btnCancel),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final count = await admin.resetAllPoints();
                        if (count != null) onToast(s.adminResetDone(count));
                      },
                      child: Text(
                        s.adminWipeAll,
                        style: const TextStyle(color: AppTheme.danger),
                      ),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(
              Icons.delete_sweep_rounded,
              size: 16,
              color: AppTheme.danger,
            ),
            label: Text(
              s.adminReset,
              style: const TextStyle(color: AppTheme.danger),
            ),
            style: TextButton.styleFrom(
              backgroundColor: AppTheme.danger.withValues(alpha: 0.08),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }
}
