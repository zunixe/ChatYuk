import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../providers/locale_provider.dart';
import '../services/points_service.dart';
import '../providers/theme_provider.dart';

/// Riwayat pencairan user sendiri.
class WithdrawalHistoryScreen extends StatefulWidget {
  const WithdrawalHistoryScreen({super.key});
  @override
  State<WithdrawalHistoryScreen> createState() => _WithdrawalHistoryScreenState();
}

class _WithdrawalHistoryScreenState extends State<WithdrawalHistoryScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await PointsService(Supabase.instance.client).myWithdrawals();
    if (!mounted) return;
    setState(() { _items = items; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(title: Text(s.withdrawHistory), backgroundColor: AppTheme.bgScreen),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text(s.withdrawNoHistory, style: TextStyle(color: AppTheme.textSecondary)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) => _card(s, _items[i]),
                  ),
                ),
    );
  }

  Widget _card(S s, Map<String, dynamic> it) {
    final coin = (it['coin_amount'] as num?)?.toInt() ?? 0;
    final payout = (it['payout_idr'] as num?)?.toInt() ?? 0;
    final status = it['status'] ?? '';
    final method = it['pay_method'] ?? '';
    final account = it['pay_account'] ?? '';
    final holder = it['pay_holder'] ?? '';
    final createdAt = it['created_at']?.toString().split('T').first ?? '';
    final txId = it['tx_id'];
    final note = it['admin_note'];

    final (color, label) = switch (status) {
      'paid' => (const Color(0xFF2E7D32), s.withdrawStatusPaid),
      'rejected' => (AppTheme.danger, s.withdrawStatusRejected),
      _ => (const Color(0xFFF9A825), s.withdrawStatusPending),
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
            child: Text('$coin 🪙  →  Rp$payout',
                style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w700)),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(label, style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
        ]),
        SizedBox(height: 6),
        Text('${_methodLabel(s, method)} • $account • $holder',
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
        Text(createdAt, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
        if (txId != null) ...[
          const SizedBox(height: 4),
          Text('${s.withdrawTxId}: $txId', style: AppText.bodySmall.copyWith(color: const Color(0xFF2E7D32))),
        ],
        if (note != null && note.toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${s.withdrawNote}: $note', style: AppText.bodySmall.copyWith(color: AppTheme.danger)),
        ],
      ]),
    );
  }

  String _methodLabel(S s, String m) => switch (m) {
        'qris' => s.withdrawMethodQris,
        'bank' => s.withdrawMethodBank,
        _ => s.withdrawMethodEwallet,
      };
}
