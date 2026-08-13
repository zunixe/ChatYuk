import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/admin_provider.dart';
import '../providers/points_provider.dart';
import '../providers/locale_provider.dart';
import '../utils.dart';
import 'admin_chat_list_screen.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _bonusCtrl = TextEditingController(text: '100');
  final _logoutCtrl = TextEditingController();
  Timer? _statsTimer;
  DateTime? _lastUpdated;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<AdminProvider>().fetchStats());
    // Polling ringan → angka statistik selalu segar tanpa loading flash.
    _statsTimer = Timer.periodic(const Duration(seconds: 30), (_) => _pollStats());
  }

  Future<void> _pollStats() async {
    final admin = context.read<AdminProvider>();
    await admin.refreshStats();
    if (mounted) setState(() => _lastUpdated = DateTime.now());
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _bonusCtrl.dispose();
    _logoutCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final s = context.watch<LocaleProvider>().s;
    final stats = admin.stats;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.bgScreen,
        appBar: AppBar(
          title: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.admin_panel_settings, size: 20, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(s.adminPanel),
          ]),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20, color: AppTheme.primary),
              onPressed: () async {
                await admin.fetchStats();
                if (mounted) setState(() => _lastUpdated = DateTime.now());
              },
            ),
          ],
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: [
              Tab(text: s.adminOverview),
              Tab(text: s.adminChatMonitor),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            admin.loading
                ? const Center(child: CircularProgressIndicator())
                : admin.error != null
                    ? _errorView(admin, s)
                    : RefreshIndicator(
                        onRefresh: () async {
                          await admin.fetchStats();
                          if (mounted) setState(() => _lastUpdated = DateTime.now());
                        },
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 24),
                          children: [
                            _lastUpdatedHeader(s),
                            const SizedBox(height: 8),
                            _statsGrid(stats, s),
                            const SizedBox(height: 8),
                            _topEarners(stats, s),
                            const SizedBox(height: 12),
                            _controls(admin, s),
                            const SizedBox(height: 12),
                            _massBonus(admin, s),
                            const SizedBox(height: 12),
                            _reportedUsers(stats, s),
                            const SizedBox(height: 12),
                            _forceLogout(s),
                            const SizedBox(height: 12),
                            _dangerZone(admin, s),
                            const SizedBox(height: 24),
                          ],
                        ),
                      ),
            const AdminChatListScreen(),
          ],
        ),
      ),
    );
  }

  Widget _errorView(AdminProvider admin, S s) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
      const SizedBox(height: 8),
      Text(admin.error!, style: const TextStyle(color: AppTheme.danger)),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: () => admin.fetchStats(), child: Text(s.btnRetry)),
    ]));
  }

  Widget _lastUpdatedHeader(S s) {
    final ts = _lastUpdated;
    if (ts == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        '${s.adminLastUpdate} ${formatRelativeTime(ts, isId: s.isId)}',
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10),
      ),
    );
  }

  Widget _statsGrid(Map<String, dynamic>? stats, S s) {
    final items = [
      (s.statsUsers, '${stats?['total_users'] ?? '-'}', Icons.people_outline, AppTheme.primary),
      (s.statsActive, '${stats?['active_today'] ?? '-'}', Icons.online_prediction, Colors.green),
      (s.statsMsgs, '${stats?['messages_today'] ?? '-'}', Icons.message_outlined, Colors.deepPurple),
      (s.statsRooms, '${stats?['rooms_active'] ?? '-'}', Icons.chat_bubble_outline, Colors.teal),
      (s.statsReg, '${stats?['registered_users'] ?? '-'}', Icons.verified_outlined, Colors.blue),
      (s.statsAnon, '${stats?['anonymous_users'] ?? '-'}', Icons.person_outline, Colors.orange),
      (s.statsAvg, '${stats?['avg_points'] ?? '-'}', Icons.trending_up, Colors.amber.shade700),
      (s.statsTotal, '${stats?['total_points'] ?? '-'}', Icons.monetization_on_outlined, Colors.pink),
    ];
    Widget cell(int i) {
      return Expanded(
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(items[i].$3, size: 15, color: items[i].$4),
            const SizedBox(height: 5),
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(items[i].$2,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)))),
            const SizedBox(height: 2),
            Text(items[i].$1, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9)),
          ]),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [cell(0), const SizedBox(width: 8), cell(1), const SizedBox(width: 8), cell(2), const SizedBox(width: 8), cell(3)]),
        const SizedBox(height: 8),
        Row(children: [cell(4), const SizedBox(width: 8), cell(5), const SizedBox(width: 8), cell(6), const SizedBox(width: 8), cell(7)]),
      ],
    );
  }

  Widget _topEarners(Map<String, dynamic>? stats, S s) {
    final earners = (stats?['top_earners'] as List?) ?? [];
    return _card(s.adminTopEarners, Icons.emoji_events_outlined, Colors.amber, [
      if (earners.isEmpty)
        Text(s.adminNoUsers, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      for (var i = 0; i < earners.length && i < 5; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(children: [
            SizedBox(
              width: 18,
              child: Text('${i + 1}', style: TextStyle(
                color: i == 0 ? Colors.amber : AppTheme.textSecondary,
                fontSize: 11, fontWeight: FontWeight.w900)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${earners[i]['nickname'] ?? '?'}',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Text('${earners[i]['points'] ?? 0} pts', style: const TextStyle(color: AppTheme.primary, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
      if ((stats?['stuck_users'] ?? 0) > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, size: 14, color: AppTheme.danger),
            const SizedBox(width: 4),
            Text('${stats!['stuck_users']} ${s.adminStuckUsers}', style: const TextStyle(color: AppTheme.danger, fontSize: 11)),
          ]),
        ),
    ]);
  }

  Widget _controls(AdminProvider admin, S s) {
    return _card(s.adminPointsSystem, Icons.toggle_on_outlined, AppTheme.primary, [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: (admin.pointsEnabled ? Colors.green : AppTheme.danger).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: admin.pointsEnabled ? Colors.green : AppTheme.danger),
            const SizedBox(width: 6),
            Text(admin.pointsEnabled ? s.adminRunning : s.adminPaused,
              style: TextStyle(color: admin.pointsEnabled ? Colors.green : AppTheme.danger, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        ),
        const Spacer(),
        Switch(
          value: admin.pointsEnabled,
          onChanged: (v) {
            admin.togglePointsSystem(v);
            context.read<PointsProvider>().refreshEnabled();
          },
          activeColor: AppTheme.primary,
        ),
      ]),
      const SizedBox(height: 2),
      Text(s.adminRealtimeDesc, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
    ]);
  }

  Widget _massBonus(AdminProvider admin, S s) {
    return _card(s.adminMassBonus, Icons.card_giftcard, Colors.amber, [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _bonusCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              labelText: s.pointsBalance,
              isDense: true,
              filled: true,
              fillColor: AppTheme.bgInput,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: () async {
            final amount = int.tryParse(_bonusCtrl.text) ?? 0;
            if (amount <= 0) return;
            final result = await admin.massBonus(amount);
            if (result != null) _toast('+$amount → ${result['affected']} users');
          },
          icon: const Icon(Icons.send_rounded, size: 16),
          label: Text(s.btnSend),
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      ]),
      const SizedBox(height: 4),
      Text(s.adminRegisteredOnly, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
    ]);
  }

  Widget _reportedUsers(Map<String, dynamic>? stats, S s) {
    final reports = (stats?['reported_users'] as List?) ?? [];
    return _card(s.adminReports, Icons.flag_outlined, Colors.orange, [
      if (reports.isEmpty)
        Text(s.adminNoReports, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      for (var i = 0; i < reports.length && i < 8; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            Expanded(
              child: Text('${reports[i]['reported_id']?.toString().substring(0, 8) ?? '?'}...',
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text('${reports[i]['report_count']}x', style: TextStyle(color: Colors.orange.shade700, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
    ]);
  }

  Widget _forceLogout(S s) {
    return _card(s.adminForceLogout, Icons.logout, Colors.orange, [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _logoutCtrl,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: s.labelUserId,
              isDense: true,
              filled: true,
              fillColor: AppTheme.bgInput,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: () {
            final uid = _logoutCtrl.text.trim();
            if (uid.isEmpty) return;
            try {
              context.read<AdminProvider>().forceLogout(uid);
              _toast('Force logout: ${uid.substring(0, 8)}...');
              _logoutCtrl.clear();
            } catch (e) {
              _toast('Failed: $e');
            }
          },
          icon: const Icon(Icons.logout, size: 16, color: Colors.orange),
          label: Text(s.adminLogout, style: const TextStyle(color: Colors.orange)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange,
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
          ),
        ),
      ]),
    ]);
  }

  Widget _dangerZone(AdminProvider admin, S s) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber_rounded, size: 20, color: AppTheme.danger),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.adminDangerZone, style: const TextStyle(color: AppTheme.danger, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(s.adminResetAllPoints, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ]),
        ),
        TextButton.icon(
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppTheme.bgCard,
                title: Text(s.adminResetAllTitle, style: const TextStyle(color: AppTheme.textPrimary)),
                content: Text(s.adminResetAllBody, style: const TextStyle(color: AppTheme.textSecondary)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.btnCancel)),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final count = await admin.resetAllPoints();
                      if (count != null) _toast('$count users reset');
                    },
                    child: Text(s.adminWipeAll, style: const TextStyle(color: AppTheme.danger)),
                  ),
                ],
              ),
            );
          },
          icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: AppTheme.danger),
          label: Text(s.adminReset, style: const TextStyle(color: AppTheme.danger)),
          style: TextButton.styleFrom(
            backgroundColor: AppTheme.danger.withValues(alpha: 0.08),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ]),
    );
  }

  Widget _card(String title, IconData icon, Color iconColor, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }
}
