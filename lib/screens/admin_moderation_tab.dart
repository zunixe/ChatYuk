import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import 'moderation_screen.dart';

/// TAB ADMIN: daftar GABUNGAN semua yang menunggu tinjauan moderasi
/// (permohonan izin lintas negara, laporan pesan, lamaran moderator),
/// dikelompokkan per negara.
///
/// Tanpa tab ini admin harus menebak negara mana yang punya permohonan.
class AdminModerationTab extends ConsumerStatefulWidget {
  const AdminModerationTab({super.key});

  @override
  ConsumerState<AdminModerationTab> createState() => _AdminModerationTabState();
}

class _AdminModerationTabState extends ConsumerState<AdminModerationTab> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res =
        await ref.read(chatProvider.notifier).adminModerationOverview();
    if (!mounted) return;
    setState(() {
      _data = res;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _list(String key) {
    final v = _data?[key];
    if (v is List) {
      return [
        for (final e in v)
          if (e is Map) Map<String, dynamic>.from(e),
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final permits = _list('permits');
    final reports = _list('reports');
    final apps = _list('applications');
    final reviews = _list('reviews');
    if (permits.isEmpty && reports.isEmpty && apps.isEmpty && reviews.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            s.moderationEmpty,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _section(
            s.moderationPermits,
            permits,
            (r) => _permitRow(s, r),
          ),
          _section(
            s.moderationReports,
            reports,
            (r) => _reportRow(s, r),
          ),
          _section(
            s.moderationReviews,
            reviews,
            (r) => _reviewRow(s, r),
          ),
          _section(
            s.moderationApplications,
            apps,
            (r) => _applicationRow(s, r),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(S s, Map<String, dynamic> r) => _tile(
        country: '${r['country'] ?? '-'}',
        title: '${r['type'] ?? ''} · ${r['sender_name'] ?? ''}',
        subtitle: '${s.moderationRoom}: ${r['room_id'] ?? '-'}',
        color: AppTheme.idle,
      );

  Widget _section(
    String title,
    List<Map<String, dynamic>> items,
    Widget Function(Map<String, dynamic>) row,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
          child: Text('$title (${items.length})', style: AppText.label),
        ),
        for (final it in items) row(it),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _tile({
    required String country,
    required String title,
    required String subtitle,
    Color? color,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(Icons.flag_rounded, color: color ?? AppTheme.primary),
        title: Text(title, style: AppText.bodyStrong),
        subtitle: Text(
          '$country · $subtitle',
          style: AppText.caption.copyWith(color: AppTheme.textSecondary),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: country.isEmpty
            ? null
            : () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ModerationScreen(country: country),
                  ),
                );
                await _load();
              },
      ),
    );
  }

  Widget _permitRow(S s, Map<String, dynamic> r) => _tile(
        country: '${r['country'] ?? ''}',
        title: '${r['nickname'] ?? r['uid'] ?? '?'}',
        subtitle: s.moderationPermitRequest,
        color: Colors.orange,
      );

  Widget _reportRow(S s, Map<String, dynamic> r) => _tile(
        country: '${r['country'] ?? ''}',
        title: '${r['reports'] ?? 0}× ${_reasonLabel(s, '${r['reason_code'] ?? ''}')}',
        subtitle: '${s.moderationRoom}: ${r['room_id'] ?? '-'}',
        color: AppTheme.danger,
      );

  Widget _applicationRow(S s, Map<String, dynamic> r) => _tile(
        country: '${r['country'] ?? ''}',
        title: '${r['nickname'] ?? r['uid'] ?? '?'}',
        subtitle: s.moderationApply,
      );

  String _reasonLabel(S s, String code) {
    switch (code) {
      case 'porn':
        return s.reportReasonPorn;
      case 'violence':
        return s.reportReasonViolence;
      case 'spam':
        return s.reportReasonSpam;
      case 'scam':
        return s.reportReasonScam;
      default:
        return s.reportReasonOther;
    }
  }
}
