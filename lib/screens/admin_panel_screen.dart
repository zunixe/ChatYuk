import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../providers/admin_provider.dart';
import '../providers/points_provider.dart';
import '../services/admin_service.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  final _bonusCtrl = TextEditingController(text: '100');
  final _logoutCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<AdminProvider>().fetchStats());
  }

  @override
  void dispose() {
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
    final stats = admin.stats;

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.admin_panel_settings, size: 20, color: AppTheme.primary),
          SizedBox(width: 8),
          Text('Admin Panel'),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, size: 20, color: AppTheme.primary), onPressed: () => admin.fetchStats()),
        ],
      ),
      body: admin.loading
          ? const Center(child: CircularProgressIndicator())
          : admin.error != null
              ? _errorView(admin)
              : RefreshIndicator(
                  onRefresh: () => admin.fetchStats(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    children: [
                      _statsGrid(stats),
                      const SizedBox(height: 8),
                      _topEarners(stats),
                      const SizedBox(height: 12),
                      _controls(admin),
                      const SizedBox(height: 12),
                      _massBonus(admin),
                      const SizedBox(height: 12),
                      _reportedUsers(stats),
                      const SizedBox(height: 12),
                      _forceLogout(),
                      const SizedBox(height: 12),
                      _dangerZone(admin),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _errorView(AdminProvider admin) {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
      const SizedBox(height: 8),
      Text(admin.error!, style: const TextStyle(color: AppTheme.danger)),
      const SizedBox(height: 8),
      ElevatedButton(onPressed: () => admin.fetchStats(), child: const Text('Retry')),
    ]));
  }

  Widget _statsGrid(Map<String, dynamic>? stats) {
    final items = [
      ('Users', '${stats?['total_users'] ?? '-'}', Icons.people_outline, AppTheme.primary),
      ('Active', '${stats?['active_today'] ?? '-'}', Icons.online_prediction, Colors.green),
      ('Msgs', '${stats?['messages_today'] ?? '-'}', Icons.message_outlined, Colors.deepPurple),
      ('Rooms', '${stats?['rooms_active'] ?? '-'}', Icons.chat_bubble_outline, Colors.teal),
      ('Reg.', '${stats?['registered_users'] ?? '-'}', Icons.verified_outlined, Colors.blue),
      ('Anon', '${stats?['anonymous_users'] ?? '-'}', Icons.person_outline, Colors.orange),
      ('Avg', '${stats?['avg_points'] ?? '-'}', Icons.trending_up, Colors.amber.shade700),
      ('Total', '${stats?['total_points'] ?? '-'}', Icons.monetization_on_outlined, Colors.pink),
    ];
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.95),
      itemCount: items.length,
      itemBuilder: (_, i) => Container(
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

  Widget _topEarners(Map<String, dynamic>? stats) {
    final earners = (stats?['top_earners'] as List?) ?? [];
    return _card('Top Earners', Icons.emoji_events_outlined, Colors.amber, [
      if (earners.isEmpty)
        const Text('No users', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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
            Text('${stats!['stuck_users']} users stuck (0 points)', style: const TextStyle(color: AppTheme.danger, fontSize: 11)),
          ]),
        ),
    ]);
  }

  Widget _controls(AdminProvider admin) {
    return _card('Points System', Icons.toggle_on_outlined, AppTheme.primary, [
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
            Text(admin.pointsEnabled ? 'Running' : 'Paused',
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
      const Text('Realtime — efek langsung ke semua device', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
    ]);
  }

  Widget _massBonus(AdminProvider admin) {
    return _card('Mass Bonus', Icons.card_giftcard, Colors.amber, [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _bonusCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Points',
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
          label: const Text('Send'),
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      ]),
      const SizedBox(height: 4),
      const Text('Hanya user registered', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
    ]);
  }

  Widget _reportedUsers(Map<String, dynamic>? stats) {
    final reports = (stats?['reported_users'] as List?) ?? [];
    return _card('Reports', Icons.flag_outlined, Colors.orange, [
      if (reports.isEmpty)
        const Text('No reports', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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

  Widget _forceLogout() {
    return _card('Force Logout', Icons.logout, Colors.orange, [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _logoutCtrl,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'User ID',
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
            AdminService(Supabase.instance.client).forceLogout(uid);
            _toast('Force logout: ${uid.substring(0, 8)}...');
            _logoutCtrl.clear();
          },
          icon: const Icon(Icons.logout, size: 16, color: Colors.orange),
          label: const Text('Logout', style: TextStyle(color: Colors.orange)),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange,
            visualDensity: VisualDensity.compact,
            side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
          ),
        ),
      ]),
    ]);
  }

  Widget _dangerZone(AdminProvider admin) {
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
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Danger Zone', style: TextStyle(color: AppTheme.danger, fontSize: 13, fontWeight: FontWeight.w700)),
            SizedBox(height: 2),
            Text('Reset all users to 50 points', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
          ]),
        ),
        TextButton.icon(
          onPressed: () {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: AppTheme.bgCard,
                title: const Text('Reset All Points?', style: TextStyle(color: AppTheme.textPrimary)),
                content: const Text('All users will have 50 points.', style: TextStyle(color: AppTheme.textSecondary)),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final count = await admin.resetAllPoints();
                      if (count != null) _toast('$count users reset');
                    },
                    child: const Text('Wipe All', style: TextStyle(color: AppTheme.danger)),
                  ),
                ],
              ),
            );
          },
          icon: const Icon(Icons.delete_sweep_rounded, size: 16, color: AppTheme.danger),
          label: const Text('Reset', style: TextStyle(color: AppTheme.danger)),
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
