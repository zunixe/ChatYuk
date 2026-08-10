import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../providers/admin_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();
    final stats = admin.stats;

    return Scaffold(
      appBar: AppBar(title: const Text('Admin Panel')),
      body: admin.loading
          ? const Center(child: CircularProgressIndicator())
          : admin.error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline, size: 48, color: AppTheme.danger),
                  const SizedBox(height: 8),
                  Text(admin.error!, style: const TextStyle(color: AppTheme.danger)),
                  const SizedBox(height: 8),
                  ElevatedButton(onPressed: () => admin.fetchStats(), child: const Text('Retry')),
                ]))
              : RefreshIndicator(
                  onRefresh: () => admin.fetchStats(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _statsGrid(stats),
                      const SizedBox(height: 16),
                      _topEarners(stats),
                      const SizedBox(height: 16),
                      _controls(admin),
                      const SizedBox(height: 16),
                      _massBonus(admin),
                      const SizedBox(height: 16),
                      _reportedUsers(stats),
                      const SizedBox(height: 16),
                      _forceLogout(),
                      const SizedBox(height: 16),
                      _dangerZone(admin),
                    ],
                  ),
                ),
    );
  }

  Widget _statsGrid(Map<String, dynamic>? stats) {
    final items = [
      ('Total Users', '${stats?['total_users'] ?? '-'}', Icons.people),
      ('Active Today', '${stats?['active_today'] ?? '-'}', Icons.online_prediction),
      ('Registered', '${stats?['registered_users'] ?? '-'}', Icons.verified_user),
      ('Anonymous', '${stats?['anonymous_users'] ?? '-'}', Icons.person_outline),
      ('Msgs Today', '${stats?['messages_today'] ?? '-'}', Icons.message),
      ('Active Rooms', '${stats?['rooms_active'] ?? '-'}', Icons.chat_bubble),
      ('Avg Points', '${stats?['avg_points'] ?? '-'}', Icons.trending_up),
      ('Total Points', '${stats?['total_points'] ?? '-'}', Icons.monetization_on),
    ];
    return GridView.builder(
      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 1.6),
      itemCount: items.length,
      itemBuilder: (_, i) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(items[i].$3, size: 16, color: AppTheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(items[i].$1, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12))),
          ]),
          const Spacer(),
          Text(items[i].$2, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  Widget _topEarners(Map<String, dynamic>? stats) {
    final earners = (stats?['top_earners'] as List?) ?? [];
    return _card('Top Earners', [
      if (earners.isEmpty) const Text('No users', style: TextStyle(color: AppTheme.textSecondary)),
      for (var i = 0; i < earners.length && i < 5; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Text('${i + 1}. ', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            Expanded(child: Text('${earners[i]['nickname'] ?? '?'}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13))),
            Text('${earners[i]['points'] ?? 0} pts', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w700, fontSize: 13)),
          ]),
        ),
      if (stats?['stuck_users'] != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('${stats!['stuck_users']} users stuck (0 points)',
            style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
        ),
    ]);
  }

  Widget _controls(AdminProvider admin) {
    return _card('Controls', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Points System', style: TextStyle(color: AppTheme.textPrimary)),
        subtitle: const Text('Global enable/disable', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        value: admin.pointsEnabled,
        onChanged: (v) => admin.togglePointsSystem(v),
      ),
    ]);
  }

  Widget _massBonus(AdminProvider admin) {
    return _card('Mass Bonus (Registered Users)', [
      Row(children: [
        SizedBox(
          width: 120,
          child: TextField(
            controller: _bonusCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(labelText: 'Amount', isDense: true),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () async {
            final amount = int.tryParse(_bonusCtrl.text) ?? 0;
            if (amount <= 0) return;
            final result = await admin.massBonus(amount);
            if (context.mounted && result != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Sent +$amount to ${result['affected']} users')));
            }
          },
          icon: const Icon(Icons.card_giftcard, size: 18),
          label: const Text('Send'),
        ),
      ]),
    ]);
  }

  Widget _reportedUsers(Map<String, dynamic>? stats) {
    final reports = (stats?['reported_users'] as List?) ?? [];
    return _card('Reported Users (Top 20)', [
      if (reports.isEmpty) const Text('No reports', style: TextStyle(color: AppTheme.textSecondary)),
      for (var i = 0; i < reports.length && i < 10; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text('${reports[i]['reported_id']?.toString().substring(0, 8) ?? '?'}...',
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12))),
            Text('${reports[i]['report_count']} reports',
              style: TextStyle(color: Colors.orange.shade300, fontSize: 12)),
          ]),
        ),
    ]);
  }

  Widget _forceLogout() {
    return _card('Force Logout', [
      Row(children: [
        Expanded(
          child: TextField(
            controller: _logoutCtrl,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: const InputDecoration(hintText: 'User ID', isDense: true),
          ),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: () {
            final uid = _logoutCtrl.text.trim();
            if (uid.isEmpty) return;
            AdminService(Supabase.instance.client).forceLogout(uid);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Force logout: ${uid.substring(0, 8)}...')));
            _logoutCtrl.clear();
          },          icon: const Icon(Icons.logout, size: 18, color: Colors.orange),
          label: const Text('Logout'),
          style: ElevatedButton.styleFrom(foregroundColor: Colors.orange),
        ),
      ]),
    ]);
  }

  Widget _dangerZone(AdminProvider admin) {
    return _card('Danger Zone', [
      const Text('⚠️ All users reset to 50 points', style: TextStyle(color: AppTheme.danger, fontSize: 12)),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.bgCard,
              title: const Text('Reset All Points?', style: TextStyle(color: Colors.white)),
              content: const Text('All users will have 50 points.', style: TextStyle(color: Colors.white70)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final count = await admin.resetAllPoints();
                    if (context.mounted && count != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$count users reset to 50 points')));
                    }
                  },
                  child: const Text('Wipe All', style: TextStyle(color: AppTheme.danger)),
                ),
              ],
            ),
          );
        },
        icon: const Icon(Icons.warning, size: 18, color: AppTheme.danger),
        label: const Text('Reset All Points'),
        style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
      ),
    ]);
  }

  Widget _card(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }
}
