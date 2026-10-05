import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../providers/admin_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/admin_error_view.dart';

/// Detail email campaign — ringkasan metrik + daftar penerima & status.
class AdminMarketingDetailScreen extends StatefulWidget {
  final int id;
  const AdminMarketingDetailScreen({super.key, required this.id});

  @override
  State<AdminMarketingDetailScreen> createState() =>
      _AdminMarketingDetailScreenState();
}

class _AdminMarketingDetailScreenState
    extends State<AdminMarketingDetailScreen> {
  @override
  void initState() {
    super.initState();
    final a = context.read<AdminProvider>();
    Future.microtask(() => a.fetchMarketingDetail(widget.id));
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    context.select<AdminProvider, int>((p) => p.revMarketing);
    final admin = context.read<AdminProvider>();
    final s = context.watch<LocaleProvider>().s;
    final data = admin.marketingDetail;
    final camp = (data?['campaign'] as Map?)?.cast<String, dynamic>();
    final recs = (data?['recipients'] as List?)
            ?.map((e) => (e as Map).cast<String, dynamic>())
            .toList() ??
        const <Map<String, dynamic>>[];

    return Scaffold(
      appBar: AppBar(title: Text('${camp?['name'] ?? s.adminMarketingTab}')),
      body: admin.marketingLoading && data == null
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.primary))
          : admin.marketingError != null && data == null
              ? AdminErrorView(
                  s: s,
                  error: admin.marketingError!,
                  onRetry: () => admin.fetchMarketingDetail(widget.id),
                )
              : RefreshIndicator(
                  onRefresh: () => admin.fetchMarketingDetail(widget.id),
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      12,
                      16,
                      MediaQuery.of(context).padding.bottom + 24,
                    ),
                    children: [
                      _metrics(s, camp),
                      const SizedBox(height: 16),
                      Text(s.adminMktRecipientList,
                          style: AppText.label.copyWith(
                            color: AppTheme.textSecondary,
                          )),
                      const SizedBox(height: 6),
                      if (recs.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: Text(
                              s.adminMktEmpty,
                              style: AppText.bodySmall
                                  .copyWith(color: AppTheme.textSecondary),
                            ),
                          ),
                        )
                      else
                        ...recs.map((r) => _recipientRow(s, r)),
                    ],
                  ),
                ),
    );
  }

  Widget _metrics(S s, Map<String, dynamic>? c) {
    int n(String k) => (c?[k] as num?)?.toInt() ?? 0;
    final sent = n('sent_count');
    String rate(int v) =>
        sent > 0 ? '${(v * 100 / sent).toStringAsFixed(1)}%' : '0%';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${c?['subject'] ?? ''}',
                    style: AppText.bodyStrong,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _box(s.adminMktStatSent, n('sent_count')),
              _box(s.adminMktStatDelivered, n('delivered_count')),
              _box(s.adminMktStatBounce, n('bounce_count')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _box(s.adminMktOpenRate, rate(n('open_count'))),
              _box(s.adminMktClickRate, rate(n('click_count'))),
              _box(s.adminMktStatUnsub, n('unsub_count')),
            ],
          ),
          if (c?['last_error'] != null) ...[
            const SizedBox(height: 10),
            Text('${c?['last_error']}',
                style: AppText.caption.copyWith(color: AppTheme.danger)),
          ],
        ],
      ),
    );
  }

  Widget _box(String label, dynamic value) {
    return Expanded(
      child: Column(
        children: [
          Text('$value', style: AppText.titleEmphasis),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style:
                  AppText.caption.copyWith(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _recipientRow(S s, Map<String, dynamic> r) {
    final status = '${r['status'] ?? 'pending'}';
    final color = switch (status) {
      'opened' => AppTheme.primary,
      'clicked' => const Color(0xFF2E7D32),
      'sent' || 'delivered' => AppTheme.textSecondary,
      'bounced' => AppTheme.danger,
      'failed' => AppTheme.danger,
      _ => AppTheme.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${r['email'] ?? ''}',
              style: AppText.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (r['opened_at'] != null)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.visibility_outlined,
                  size: 15, color: AppTheme.primary),
            ),
          if (r['clicked_at'] != null)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.ads_click_rounded,
                  size: 15, color: Color(0xFF2E7D32)),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(status,
                style: AppText.caption.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}
