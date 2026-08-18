import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/gifts.dart';
import '../providers/locale_provider.dart';
import '../services/points_service.dart';
import '../providers/theme_provider.dart';

/// Dashboard pendapatan platform (admin): potongan gift + ringkasan pencairan.
class AdminRevenueScreen extends StatefulWidget {
  const AdminRevenueScreen({super.key});
  @override
  State<AdminRevenueScreen> createState() => _AdminRevenueScreenState();
}

class _AdminRevenueScreenState extends State<AdminRevenueScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await PointsService(Supabase.instance.client).adminRevenueOverview();
    if (!mounted) return;
    setState(() { _data = data; _loading = false; });
  }

  String _fmt(int n) {
    final buf = StringBuffer();
    final s = n.toString();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  Map<String, dynamic> _gift() =>
      (_data?['gift'] is Map) ? Map<String, dynamic>.from(_data!['gift'] as Map) : {};
  Map<String, dynamic> _withdraw() =>
      (_data?['withdraw'] is Map) ? Map<String, dynamic>.from(_data!['withdraw'] as Map) : {};
  Map<String, dynamic> _settings() =>
      (_data?['settings'] is Map) ? Map<String, dynamic>.from(_data!['settings'] as Map) : {};

  String _giftName(S s, String id) {
    final g = giftById(id);
    if (g == null) return id;
    return '${g.emoji} ${s.isId ? g.nameId : g.nameEn}';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final s = context.watch<LocaleProvider>().s;
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text(s.adminRevenueTitle),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, size: 20, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator())
          : (_data == null || _data!.isEmpty)
              ? Center(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.pie_chart_outline, size: 48, color: AppTheme.textSecondary),
                    SizedBox(height: 8),
                    Text(s.adminRevenueNoData, style: TextStyle(color: AppTheme.textSecondary)),
                  ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 24),
                    children: [
                      _giftSection(s),
                      const SizedBox(height: 12),
                      _topGifts(s),
                      const SizedBox(height: 12),
                      _withdrawSection(s),
                      const SizedBox(height: 12),
                      _settingsSection(s),
                    ],
                  ),
                ),
    );
  }

  Widget _card(String title, IconData icon, Color iconColor, List<Widget> children) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: iconColor),
          SizedBox(width: 8),
          Text(title, style: AppText.caption.copyWith(color: AppTheme.textSecondary, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }

  Widget _metric(String label, String value, Color color, {String? sub}) {
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: AppText.title.copyWith(color: color, fontWeight: FontWeight.w800)),
        SizedBox(height: 2),
        Text(label, style: AppText.micro.copyWith(color: AppTheme.textSecondary, fontWeight: FontWeight.w400)),
        if (sub != null) Text(sub, style: AppText.micro.copyWith(color: AppTheme.textSecondary, fontWeight: FontWeight.w400)),
      ]),
    );
  }

  Widget _giftSection(S s) {
    final g = _gift();
    return _card(s.adminRevenueGift, Icons.card_giftcard, Colors.pinkAccent, [
      Row(children: [
        _metric(s.adminRevenueCutTotal, 'Rp${_fmt((g['cut_total'] as num?)?.toInt() ?? 0)}', AppTheme.primary),
        _metric(s.adminRevenueGross, 'Rp${_fmt((g['gross_total'] as num?)?.toInt() ?? 0)}', Colors.deepPurple),
        _metric(s.adminRevenueGiftCount, '${g['count_total'] ?? 0}', Colors.teal),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        _metric(s.adminRevenueCutToday, 'Rp${_fmt((g['cut_today'] as num?)?.toInt() ?? 0)}', Colors.pinkAccent,
            sub: '${g['count_today'] ?? 0} gift'),
      ]),
    ]);
  }

  Widget _topGifts(S s) {
    final list = (_gift()['top_gifts'] as List?) ?? [];
    return _card(s.adminRevenueTopGifts, Icons.emoji_events_outlined, Colors.amber, [
      if (list.isEmpty)
        Text(s.adminRevenueNoData, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
      for (final t in list)
        Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(
              child: Text(_giftName(s, '${t['gift'] ?? ''}'),
                  style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text('${t['count'] ?? 0}x', style: AppText.caption.copyWith(color: AppTheme.textSecondary)),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Text('+Rp${_fmt((t['cut'] as num?)?.toInt() ?? 0)}',
                  style: AppText.caption.copyWith(color: const Color(0xFFB45309), fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
    ]);
  }

  Widget _withdrawSection(S s) {
    final w = _withdraw();
    return _card(s.adminRevenueWithdraw, Icons.currency_exchange, const Color(0xFF2E7D32), [
      Row(children: [
        _metric(s.adminRevenuePending, '${w['pending_count'] ?? 0}',
            const Color(0xFFF9A825), sub: 'Rp${_fmt((w['pending_payout_idr'] as num?)?.toInt() ?? 0)}'),
        _metric(s.adminRevenuePaid, '${w['paid_count'] ?? 0}',
            const Color(0xFF2E7D32), sub: 'Rp${_fmt((w['paid_payout_idr'] as num?)?.toInt() ?? 0)}'),
        _metric(s.adminRevenueRejected, '${w['rejected_count'] ?? 0}',
            AppTheme.danger, sub: 'Rp${_fmt((w['rejected_payout_idr'] as num?)?.toInt() ?? 0)}'),
      ]),
    ]);
  }

  Widget _settingsSection(S s) {
    final st = _settings();
    final enabled = st['points_enabled'] == true;
    return _card(s.adminRevenueSettings, Icons.tune, Colors.blueGrey, [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${s.adminRevenueCutPct}: ${st['gift_cut_pct'] ?? '-'}%',
                style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary)),
            SizedBox(height: 4),
            Text('${s.adminRevenueRate}: ${st['withdraw_rate_idr'] ?? '-'}',
                style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary)),
            SizedBox(height: 4),
            Text('${s.withdrawAmount} min: ${st['withdraw_min_coins'] ?? '-'}',
                style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: (enabled ? Colors.green : AppTheme.danger).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: enabled ? Colors.green : AppTheme.danger),
            const SizedBox(width: 6),
            Text(enabled ? s.adminRunning : s.adminPaused,
                style: AppText.bodySmall.copyWith(color: enabled ? Colors.green : AppTheme.danger, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    ]);
  }
}
