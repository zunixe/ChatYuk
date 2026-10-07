import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;

import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../providers/admin_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/theme_provider.dart';
import '../widgets/admin_error_view.dart';
import 'admin_marketing_composer_screen.dart';
import 'admin_marketing_detail_screen.dart';
import '../providers/riverpod/admin_provider.dart';

/// Admin: tab Marketing — daftar email campaign + metrik.
class AdminMarketingTab extends ConsumerStatefulWidget {
  const AdminMarketingTab({super.key});

  @override
  ConsumerState<AdminMarketingTab> createState() => _AdminMarketingTabState();
}

class _AdminMarketingTabState extends ConsumerState<AdminMarketingTab> {
  @override
  void initState() {
    super.initState();
    final a = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    Future.microtask(a.fetchMarketing);
  }

  Future<void> _openComposer({Map<String, dynamic>? existing}) async {
    final a = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AdminMarketingComposerScreen(campaign: existing),
      ),
    );
    if (changed == true) a.fetchMarketing();
  }

  Future<void> _openDetail(int id) async {
    final a = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AdminMarketingDetailScreen(id: id)),
    );
    a.fetchMarketing();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    // Rebuild hanya saat domain MARKETING berubah.
    ref.watch(adminProvider.select((p) => p.revMarketing));
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    final s = ref.watch(localeProvider).s;
    final stats = admin.marketingStats;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(s.adminMarketingTab,
                    style: AppText.titleEmphasis),
              ),
              FilledButton.icon(
                onPressed: () => _openComposer(),
                icon: const Icon(Icons.add, size: 18),
                label: Text(s.adminMktNewCampaign),
              ),
            ],
          ),
        ),
        Expanded(
          child: admin.marketingLoading && admin.marketingCampaigns.isEmpty
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.primary))
              : admin.marketingError != null &&
                      admin.marketingCampaigns.isEmpty
                  ? AdminErrorView(
                      s: s,
                      error: admin.marketingError!,
                      onRetry: () => admin.fetchMarketing(),
                    )
                  : RefreshIndicator(
                      onRefresh: () => admin.fetchMarketing(),
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          8,
                          16,
                          MediaQuery.of(context).padding.bottom + 24,
                        ),
                        children: [
                          _statsCard(s, stats),
                          const SizedBox(height: 16),
                          if (admin.marketingCampaigns.isEmpty)
                            _emptyCard(s)
                          else
                            ...admin.marketingCampaigns.map(
                              (c) => _campaignTile(s, admin, c),
                            ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _statsCard(S s, Map<String, dynamic>? stats) {
    int n(String k) => (stats?[k] as num?)?.toInt() ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.mail_outline_rounded,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                '${n('registered_with_email')} ${s.adminMktRecipients}',
                style: AppText.bodyStrong,
              ),
              const Spacer(),
              Text(
                '${n('suppressed')} ${s.adminMktStatUnsub}',
                style: AppText.caption
                    .copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _metric(s.adminMktStatSent, n('sent_total')),
              _metric(s.adminMktStatDelivered, n('delivered_total')),
              _metric(s.adminMktStatOpen, n('open_total')),
              _metric(s.adminMktStatClick, n('click_total')),
              _metric(s.adminMktStatBounce, n('bounce_total')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: AppText.titleEmphasis),
        Text(label,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _emptyCard(S s) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Text(
        s.adminMktEmpty,
        style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
      ),
    );
  }

  Widget _campaignTile(S s, AdminProvider a, Map<String, dynamic> c) {
    final id = (c['id'] as num?)?.toInt() ?? 0;
    final total = (c['total_recipients'] as num?)?.toInt() ?? 0;
    final sent = (c['sent_count'] as num?)?.toInt() ?? 0;
    final opened = (c['open_count'] as num?)?.toInt() ?? 0;
    final clicked = (c['click_count'] as num?)?.toInt() ?? 0;
    final status = '${c['status'] ?? 'draft'}';
    final openRate = sent > 0 ? (opened * 100 / sent).toStringAsFixed(1) : '0';
    final clickRate =
        sent > 0 ? (clicked * 100 / sent).toStringAsFixed(1) : '0';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openDetail(id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${c['name'] ?? '(tanpa nama)'}',
                      style: AppText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _statusChip(s, status),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${c['subject'] ?? ''}',
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _mini(s.adminMktStatSent, sent),
                  const SizedBox(width: 16),
                  _mini(s.adminMktOpenRate, double.tryParse(openRate) ?? 0,
                      suffix: '%'),
                  const SizedBox(width: 16),
                  _mini(s.adminMktClickRate, double.tryParse(clickRate) ?? 0,
                      suffix: '%'),
                  const Spacer(),
                  Text('$total ${s.adminMktRecipients}',
                      style: AppText.caption
                          .copyWith(color: AppTheme.textSecondary)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _openComposer(existing: c),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: Text(s.adminMktSaveDraft),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const Spacer(),
                  if (status == 'draft' || status == 'failed')
                    FilledButton.icon(
                      onPressed: () => _confirmSend(s, a, id, c),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: Text(s.adminMktSend),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mini(String label, dynamic value, {String suffix = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value$suffix', style: AppText.bodyStrong),
        Text(label,
            style: AppText.caption.copyWith(color: AppTheme.textSecondary)),
      ],
    );
  }

  Widget _statusChip(S s, String status) {
    final (label, color) = switch (status) {
      'queued' => (s.adminMktStatusQueued, const Color(0xFFB8860B)),
      'sending' => (s.adminMktStatusSending, AppTheme.primary),
      'sent' => (s.adminMktStatusSent, const Color(0xFF2E7D32)),
      'failed' => (s.adminMktStatusFailed, AppTheme.danger),
      _ => (s.adminMktStatusDraft, AppTheme.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _confirmSend(
    S s,
    AdminProvider a,
    int id,
    Map<String, dynamic> c,
  ) async {
    final seg = (c['segment'] as Map?)?.cast<String, dynamic>() ??
        {'type': 'all_registered'};
    final n = await a.estimateSegment(seg);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.adminMktSendConfirmTitle),
        content: Text(s.adminMktSendConfirmMsg(n)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.adminMktSend),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await a.sendCampaign(id);
    if (!mounted) return;
    final msg = res.startsWith('ok:')
        ? s.adminMktSentQueue
        : '${s.adminMktSendFail}: $res';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
