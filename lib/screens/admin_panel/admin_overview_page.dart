import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;

import '../../config/strings.dart';
import '../../config/strings_admin.dart';
import '../../config/theme.dart';
import '../../providers/riverpod/admin_provider.dart';
import '../../providers/riverpod/locale_provider.dart';
import '../../widgets/admin_error_view.dart';
import '../../widgets/app_gesture.dart';
import 'widgets/app_stats_card.dart';
import 'widgets/geo_stats_card.dart';
import 'widgets/overview_cards.dart';
import 'widgets/registrationschart_card.dart';
import 'widgets/stat_detail_sheet.dart';
import 'widgets/stats_status.dart';
import 'widgets/storageusage_card.dart';
import 'widgets/usermap_card.dart';

/// Menu "Ringkasan" panel admin — statistik user, peta, storage, dsb.
class AdminOverviewPage extends ConsumerStatefulWidget {
  const AdminOverviewPage({super.key});
  @override
  ConsumerState<AdminOverviewPage> createState() => _AdminOverviewPageState();
}

class _AdminOverviewPageState extends ConsumerState<AdminOverviewPage> {
  final _logoutCtrl = TextEditingController();

  /// Daftar user Ghost Mode — dimuat SEKALI (bukan di dalam `build`, karena
  /// `FutureBuilder(future: ...di-build-di-sini)` akan memanggil RPC setiap
  /// rebuild → spam request). Di-refresh saat sheet dibuka.
  Future<List<Map<String, dynamic>>>? _ghostFuture;

  @override
  void dispose() {
    _logoutCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final admin = ref.watch(adminProvider);
    final s = ref.watch(localeProvider).s;
    final stats = admin.stats;
    // Layar error penuh HANYA bila memang belum ada data sama sekali
    // (cold start + offline). Kalau data lama ada → tetap tampilkan + banner.
    final noData = stats == null || stats.isEmpty;
    if (admin.error != null && noData) {
      return AdminErrorView(
        s: s,
        error: admin.error!,
        onRetry: () => admin.fetchStats(),
      );
    }
    if (admin.loading && noData) {
      return const Center(child: CircularProgressIndicator());
    }
    return RefreshIndicator(
      onRefresh: () async {
        // force = server hitung ulang sekarang (lewati cache 5 mnt).
        await admin.fetchStats(force: true);
        // List user per kartu (anon/dll) di-cache terpisah 60 dtk —
        // buang juga supaya sheet berikutnya segar.
        admin.invalidateStatsDetail();
        markAdminStatsUpdated();
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        children: [
          if (admin.error != null) ...[
            AdminStaleBanner(s: s),
            const SizedBox(height: 8),
          ],
          AdminLastUpdatedHeader(s: s),
          const SizedBox(height: 8),
          _statsGrid(stats, s),
          const SizedBox(height: 12),
          AdminAppStatsCard(stats: stats, s: s),
          const SizedBox(height: 12),
          const AdminStorageUsageCard(),
          const SizedBox(height: 12),
          const AdminRegistrationsChartCard(),
          const SizedBox(height: 12),
          const AdminGeoStatsCard(),
          const SizedBox(height: 12),
          const AdminUserMapCard(),
          const SizedBox(height: 12),
          ReportedUsersCard(stats: stats, s: s),
          const SizedBox(height: 12),
          PrivacyUsersCard(stats: stats, s: s),
          const SizedBox(height: 12),
          ForceLogoutCard(s: s, logoutCtrl: _logoutCtrl, onToast: _toast),
          const SizedBox(height: 12),
          DangerZoneCard(admin: admin, s: s, onToast: _toast),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _statCell({
    required IconData icon,
    required Color color,
    required Widget value,
    required String label,
    VoidCallback? onTap,
  }) {
    return Material(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(10),
      child: AppGestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(height: 5),
              Flexible(
                child: FittedBox(fit: BoxFit.scaleDown, child: value),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: AppText.micro.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statsGrid(Map<String, dynamic>? stats, S s) {
    final items = [
      (s.statsUsers, '${stats?['total_users'] ?? '-'}', Icons.people_outline,
          AppTheme.primary, 'users_all'),
      (s.statsActive, '${stats?['active_today'] ?? '-'}',
          Icons.online_prediction, Colors.green, 'users_active'),
      (s.statsMsgs, '${stats?['messages_today'] ?? '-'}',
          Icons.message_outlined, Colors.deepPurple, 'messages_today'),
      (s.statsRooms, '${stats?['rooms_active'] ?? '-'}',
          Icons.chat_bubble_outline, Colors.teal, 'rooms_active'),
      (s.statsReg, '${stats?['registered_users'] ?? '-'}',
          Icons.verified_outlined, Colors.blue, 'users_registered'),
      (s.statsAnon, '${stats?['anonymous_users'] ?? '-'}',
          Icons.person_outline, Colors.orange, 'users_anonymous'),
    ];
    final valueStyle = AppText.titleEmphasis.copyWith(
      color: AppTheme.textPrimary,
    );
    Widget cell(int i) => Expanded(
          child: _statCell(
            icon: items[i].$3,
            color: items[i].$4,
            value: Text(items[i].$2, style: valueStyle),
            label: items[i].$1,
            onTap: () => showStatDetailSheet(context, items[i]),
          ),
        );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          cell(0),
          const SizedBox(width: 8),
          cell(1),
          const SizedBox(width: 8),
          cell(2),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          cell(3),
          const SizedBox(width: 8),
          cell(4),
          const SizedBox(width: 8),
          cell(5),
        ]),
        const SizedBox(height: 8),
        // BARIS GHOST: user yang membeli "mode invisible" (Ghost Mode).
        // Sumber: RPC admin_ghost_users.
        Row(
          children: [
            Expanded(
              child: _statCell(
                icon: Icons.visibility_off_outlined,
                color: Colors.deepPurple,
                onTap: _showGhostUsers,
                label: s.adminGhostLabel,
                value: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _ghostFuture ??=
                      ref.read(adminProvider).fetchGhostUsers(),
                  builder: (context, snap) => Text(
                    snap.hasData
                        ? '${snap.data!.length}'
                        : (snap.hasError ? '-' : '…'),
                    style: valueStyle,
                  ),
                ),
              ),
            ),
            // Baris ini hanya 1 kartu → isi 2 slot sisa supaya grid tetap
            // 3 kolom (lebar kartu konsisten dgn baris di atas).
            const SizedBox(width: 8),
            const Spacer(flex: 2),
          ],
        ),
      ],
    );
  }

  /// Daftar user yang sedang Ghost Mode (invisible berbayar).
  Future<void> _showGhostUsers() async {
    final s = ref.read(localeProvider).s;
    // Refresh data setiap sheet dibuka (kartu ikut ter-update), sekali saja.
    final future = ref.read(adminProvider).fetchGhostUsers();
    setState(() => _ghostFuture = future);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: future,
        builder: (c, snap) {
          if (!snap.hasData) {
            return const SizedBox(
              height: 160,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final rows = snap.data!;
          if (rows.isEmpty) {
            return SizedBox(
              height: 160,
              child: Center(child: Text(s.adminGhostEmpty)),
            );
          }
          return SafeArea(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: rows.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: AppTheme.divider,
              ),
              itemBuilder: (c2, i) {
                final r = rows[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.visibility_off_outlined,
                    size: 20,
                    color: Colors.deepPurple,
                  ),
                  title: Text(
                    '${r['nickname'] ?? '-'}',
                    style: AppText.bodyStrong,
                  ),
                  subtitle: Text(
                    s.adminGhostSubtitle(
                      '${r['status'] ?? '-'}',
                      '${r['ghost_sisa_jam'] ?? '-'}',
                    ),
                    style: AppText.bodySmall.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
