import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../widgets/chat_info_snack.dart';

/// Konsol MODERASI untuk satu negara: laporan pesan, permohonan izin kirim
/// media lintas negara, dan lamaran moderator.
///
/// Hanya bisa dibuka oleh moderator negara tsb atau admin (server menolak
/// lewat RPC `moderator_console` — UI ini tidak menyimpan data sensitif).
class ModerationScreen extends ConsumerStatefulWidget {
  const ModerationScreen({super.key, required this.country});

  final String country;

  @override
  ConsumerState<ModerationScreen> createState() => _ModerationScreenState();
}

class _ModerationScreenState extends ConsumerState<ModerationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ref
        .read(chatProvider.notifier)
        .moderatorConsole(widget.country);
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

  S get _s => ref.read(localeProvider).s;

  Future<void> _decideApplication(int id, bool approve) async {
    await ref
        .read(chatProvider.notifier)
        .decideModeratorApplication(id, approve: approve);
    if (!mounted) return;
    showChatSnack(context, _s.moderationUpdated);
    await _load();
  }

  Future<void> _decidePermit(String uid, bool approve) async {
    await ref.read(chatProvider.notifier).decideCountryPermit(
          uid,
          widget.country,
          approve: approve,
        );
    if (!mounted) return;
    showChatSnack(context, _s.moderationUpdated);
    await _load();
  }

  Future<void> _hideReported(String messageId, String action) async {
    if (action == 'hide') {
      await ref
          .read(chatProvider.notifier)
          .moderatorHideMessage(messageId, hide: true);
    }
    await ref
        .read(chatProvider.notifier)
        .resolveMessageReports(messageId, action: action);
    if (!mounted) return;
    showChatSnack(context, _s.moderationUpdated);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(title: Text('${s.moderationTitle} · ${widget.country}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
          ? Center(child: Text(s.errGeneric))
          : TabBarView(
              controller: _tabs,
              children: [
                _reportsTab(s),
                _permitsTab(s),
                _applicationsTab(s),
              ],
            ),
      bottomNavigationBar: _loading || _data == null
          ? null
          : Material(
              color: AppTheme.bgCard,
              child: TabBar(
                controller: _tabs,
                tabs: [
                  Tab(text: '${s.moderationReports} (${_list('reports').length})'),
                  Tab(text: '${s.moderationPermits} (${_list('permits').length})'),
                  Tab(
                    text:
                        '${s.moderationApplications} (${_list('applications').length})',
                  ),
                ],
              ),
            ),
    );
  }

  Widget _empty(S s) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            s.moderationEmpty,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ),
      );

  Widget _reportsTab(S s) {
    final items = _list('reports');
    if (items.isEmpty) return _empty(s);
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = items[i];
        final mid = '${r['message_id'] ?? ''}';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${r['reports'] ?? 0}× ${_reasonLabel(s, '${r['reason_code'] ?? ''}')}',
                  style: AppText.bodyStrong,
                ),
                const SizedBox(height: 2),
                Text(
                  '${s.moderationRoom}: ${r['room_id'] ?? '-'}',
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => _hideReported(mid, 'hide'),
                        child: Text(s.moderationHide),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _hideReported(mid, 'dismissed'),
                        child: Text(s.moderationIgnore),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _permitsTab(S s) {
    final items = _list('permits');
    if (items.isEmpty) return _empty(s);
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final p = items[i];
        final uid = '${p['uid'] ?? ''}';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p['nickname'] ?? uid}', style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  s.moderationPermitRequest,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => _decidePermit(uid, true),
                        child: Text(s.moderationApprove),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _decidePermit(uid, false),
                        child: Text(s.moderationReject),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _applicationsTab(S s) {
    final items = _list('applications');
    if (items.isEmpty) return _empty(s);
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final a = items[i];
        final id = (a['id'] as num?)?.toInt() ?? 0;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a['nickname'] ?? a['uid']}', style: AppText.bodyStrong),
                if ('${a['reason'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${a['reason']}',
                    style: AppText.caption.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => _decideApplication(id, true),
                        child: Text(s.moderationApprove),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _decideApplication(id, false),
                        child: Text(s.moderationReject),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

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
