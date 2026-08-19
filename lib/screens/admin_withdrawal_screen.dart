import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/locale_provider.dart';
import '../services/points_service.dart';
import '../providers/theme_provider.dart';

/// Review pencairan (admin). Setujui dibayar / tolak (refund earned).
class AdminWithdrawalScreen extends StatefulWidget {
  const AdminWithdrawalScreen({super.key});
  @override
  State<AdminWithdrawalScreen> createState() => _AdminWithdrawalScreenState();
}

class _AdminWithdrawalScreenState extends State<AdminWithdrawalScreen>
    with SingleTickerProviderStateMixin {
  final _txCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String _tab = 'pending';
  static const _tabs = ['pending', 'paid', 'rejected'];
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(_onTabChanged);
    _load();
  }

  void _onTabChanged() {
    if (_tabCtrl.indexIsChanging) return;
    final tab = _tabs[_tabCtrl.index];
    if (tab == _tab) return;
    _tab = tab;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await PointsService(Supabase.instance.client).adminWithdrawals(_tab);
    if (!mounted) return;
    setState(() { _items = items; _loading = false; });
  }

  Future<void> _pay(Map<String, dynamic> it) async {
    final s = context.read<LocaleProvider>().s;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.withdrawPayConfirm),
        content: TextField(
          controller: _txCtrl,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(labelText: s.withdrawPayTxId, labelStyle: TextStyle(color: AppTheme.textSecondary)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.btnConfirm, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await PointsService(Supabase.instance.client).adminWithdrawalReview(
        requestId: it['id'], action: 'pay', note: null, txId: _txCtrl.text.trim());
      _txCtrl.clear();
      messenger.showSnackBar(SnackBar(content: Text(s.withdrawPaidToast)));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${s.withdrawFailed}: $e')));
    }
  }

  Future<void> _reject(Map<String, dynamic> it) async {
    final s = context.read<LocaleProvider>().s;
    final messenger = ScaffoldMessenger.of(context);
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text(s.withdrawRejectTitle, style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: _noteCtrl,
          maxLines: 2,
          style: TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(labelText: s.withdrawNote, labelStyle: TextStyle(color: AppTheme.textSecondary)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.btnCancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(ctx, _noteCtrl.text.trim()),
            child: Text(s.btnReject, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (note == null) return;
    try {
      await PointsService(Supabase.instance.client).adminWithdrawalReview(
        requestId: it['id'], action: 'reject', note: note.isEmpty ? null : note, txId: null);
      _noteCtrl.clear();
      messenger.showSnackBar(SnackBar(content: Text(s.withdrawRejectedToast)));
      await _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${s.withdrawFailed}: $e')));
    }
  }

  @override
  void dispose() {
    _tabCtrl.removeListener(_onTabChanged);
    _tabCtrl.dispose();
    _txCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppTheme.bgScreen,
        appBar: AppBar(
          title: Text(s.adminWithdrawTitle),
          bottom: TabBar(
            controller: _tabCtrl,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: AppText.bodyStrong.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            unselectedLabelStyle: AppText.body.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
            tabs: [
              Tab(text: s.withdrawStatusPending),
              Tab(text: s.withdrawStatusPaid),
              Tab(text: s.withdrawStatusRejected),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabCtrl,
          children: _tabs.map((t) => _listTab(s, t)).toList(),
        ),
      ),
    );
  }

  Widget _listTab(S s, String tab) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          TextButton(onPressed: () { _tab = tab; _load(); }, child: Text(s.btnRefresh)),
        ]),
      ),
      Expanded(child: _listBody(s, tab)),
    ]);
  }

  Widget _listBody(S s, String tab) {
    if (_loading && tab == _tab) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return Center(child: Text(s.withdrawNoRequests, style: TextStyle(color: AppTheme.textSecondary)));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (ctx, i) => _itemCard(s, _items[i]),
      ),
    );
  }

  Widget _itemCard(S s, Map<String, dynamic> it) {
    final status = it['status'] ?? '';
    final coin = (it['coin_amount'] as num?)?.toInt() ?? 0;
    final payout = (it['payout_idr'] as num?)?.toInt() ?? 0;
    final method = it['pay_method'] ?? '';
    final account = it['pay_account'] ?? '';
    final holder = it['pay_holder'] ?? '';
    final nickname = it['nickname'] ?? '';
    final email = it['email'] ?? '';
    final createdAt = it['created_at']?.toString().split('T').first ?? '';
    final txId = it['tx_id'];
    final note = it['admin_note'];

    final color = switch (status) {
      'paid' => const Color(0xFF2E7D32),
      'rejected' => AppTheme.danger,
      _ => const Color(0xFFF9A825),
    };

    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('$nickname (${email.isEmpty ? '?' : email})',
                style: AppText.titleEmphasis.copyWith(fontWeight: FontWeight.w700))
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(_statusLabel(s, status), style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
        ]),
        SizedBox(height: 6),
        Text('$coin 🪙 → Rp$payout', style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w600)),
        Text('${_methodLabel(s, method)} • $account • $holder', style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
        Text('$createdAt', style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
        if (txId != null) ...[
          const SizedBox(height: 4),
          Text('${s.withdrawTxId}: $txId', style: AppText.bodySmall.copyWith(color: const Color(0xFF2E7D32)),)
        ],
        if (note != null && note.toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${s.withdrawNote}: $note', style: AppText.bodySmall.copyWith(color: AppTheme.danger)),
        ],
        if (status == 'pending') ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger, side: const BorderSide(color: AppTheme.danger)),
                onPressed: () => _reject(it),
                icon: const Icon(Icons.close, size: 16),
                label: Text(s.btnReject),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
                onPressed: () => _pay(it),
                icon: const Icon(Icons.check, size: 16),
                label: Text(s.withdrawPay, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ]),
        ],
      ]),
    );
  }

  String _statusLabel(S s, String status) => switch (status) {
        'paid' => s.withdrawStatusPaid,
        'rejected' => s.withdrawStatusRejected,
        _ => s.withdrawStatusPending,
      };

  String _methodLabel(S s, String m) => switch (m) {
        'qris' => s.withdrawMethodQris,
        'bank' => s.withdrawMethodBank,
        _ => s.withdrawMethodEwallet,
      };
}
