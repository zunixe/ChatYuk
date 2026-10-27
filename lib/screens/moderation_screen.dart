import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../providers/riverpod/auth_provider.dart';
import '../providers/riverpod/chat_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../widgets/chat_info_snack.dart';
import '../widgets/message/message_image.dart';

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
  late final TabController _tabs = TabController(length: 4, vsync: this);
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

  Future<void> _resolveReview(String messageId, {required bool hide}) async {
    await ref
        .read(chatProvider.notifier)
        .moderatorResolveReview(messageId, hide: hide);
    if (!mounted) return;
    showChatSnack(context, _s.moderationUpdated);
    await _load();
  }

  /// Batalkan penyembunyian (moderator salah sembunyikan).
  Future<void> _unhide(String messageId) async {
    await ref
        .read(chatProvider.notifier)
        .moderatorHideMessage(messageId, hide: false);
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
      appBar: AppBar(
        title: Text('${s.moderationTitle} · ${widget.country}'),
        actions: [
          IconButton(
            tooltip: s.moderationAddModerator,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: _openCandidates,
          ),
          if (ref.read(authProvider.notifier).isRealAdmin)
            IconButton(
              tooltip: s.moderationSearchUser,
              icon: const Icon(Icons.search_rounded),
              onPressed: _searchUserToAppoint,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
          // RPC menolak (bukan moderator/admin negara ini) atau gagal →
          // beri pesan yang benar + jalan keluar, bukan "terjadi kesalahan".
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      s.moderationNotModeratorHere,
                      textAlign: TextAlign.center,
                      style: AppText.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(s.btnCancel),
                    ),
                  ],
                ),
              ),
            )
          : TabBarView(
              controller: _tabs,
              children: [
                _reviewsTab(s),
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
                isScrollable: true,
                tabs: [
                  Tab(
                    text:
                        '${s.moderationReviews} (${_list('reviews').length})',
                  ),
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

  /// Thumbnail media (path storage Supabase / URL) untuk verifikasi cepat.
  Widget _thumb(String path) {
    if (path.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 96,
        height: 96,
        child: MessageImage(
          imageData: path,
          chatKey: 'moderation',
          messageId: path,
        ),
      ),
    );
  }

  /// Tinjauan media borderline (skor NSFW 0.50–0.75).
  Widget _reviewsTab(S s) {
    final items = _list('reviews');
    if (items.isEmpty) return _empty(s);
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = items[i];
        final mid = '${r['message_id'] ?? ''}';
        final path = '${r['image_path'] ?? ''}';
        final text = '${r['text'] ?? ''}';
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _thumb(path),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${r['type'] ?? ''} · ${r['sender_name'] ?? ''}',
                            style: AppText.bodyStrong,
                          ),
                          if (text.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              text,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            '${s.moderationRoom}: ${r['room_id'] ?? '-'}',
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonal(
                        onPressed: () => _resolveReview(mid, hide: false),
                        child: Text(s.moderationReviewOk),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _resolveReview(mid, hide: true),
                        child: Text(s.moderationHide),
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

  Widget _reportsTab(S s) {
    final items = _list('reports');
    if (items.isEmpty) return _empty(s);
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _thumb('${r['image_path'] ?? ''}'),
                    if ('${r['image_path'] ?? ''}'.isNotEmpty)
                      const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ('${r['text'] ?? ''}'.isNotEmpty)
                            Text(
                              '${r['text']}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.caption.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          if (r['hidden'] == true) ...[
                            const SizedBox(height: 6),
                            OutlinedButton(
                              onPressed: () => _unhide(mid),
                              child: Text(s.moderationUnhide),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
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
      separatorBuilder: (_, _) => const SizedBox(height: 8),
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
      separatorBuilder: (_, _) => const SizedBox(height: 8),
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

  /// Admin: cari user mana pun (di luar kandidat) untuk diangkat.
  Future<void> _searchUserToAppoint() async {
    final s = _s;
    final ctrl = TextEditingController();
    var results = <Map<String, dynamic>>[];
    var busy = false;
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Future<void> run() async {
            final q = ctrl.text.trim();
            if (q.length < 2) return;
            setSheet(() => busy = true);
            final list = await ref
                .read(chatProvider.notifier)
                .adminSearchUsers(q);
            if (!ctx.mounted) return;
            setSheet(() {
              results = list;
              busy = false;
            });
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: ctrl,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => run(),
                      decoration: InputDecoration(
                        hintText: s.moderationSearchUser,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search_rounded),
                          onPressed: run,
                        ),
                      ),
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    )
                  else
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: results.length,
                        itemBuilder: (_, i) {
                          final u = results[i];
                          return ListTile(
                            leading: const Icon(Icons.person_outline_rounded),
                            title: Text('${u['nickname'] ?? u['uid']}'),
                            subtitle: Text(
                              '${u['country'] ?? '-'} · ${u['messages'] ?? 0} pesan',
                            ),
                            onTap: () => Navigator.pop(ctx, u),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (picked == null || !mounted) return;
    final uid = '${picked['uid'] ?? ''}';
    if (uid.isEmpty) return;
    final res = await ref.read(chatProvider.notifier).moderatorSetColleague(
          widget.country,
          uid,
          grant: true,
        );
    if (!mounted) return;
    showChatSnack(
      context,
      _colleagueMessage(res, s),
    );
    await _load();
  }

  /// Pesan hasil angkat copot moderator — `slots_full` punya pesan sendiri
  /// (batas 2 moderator aktif per negara).
  String _colleagueMessage(Map<String, dynamic> res, S s) {
    if (res['ok'] == true) return s.moderationAppointed;
    if (res['error'] == 'slots_full') return s.moderationSlotsFull;
    return s.errGeneric;
  }

  /// Angkat moderator dari KONTRIBUTOR negara ini (>=50 pesan).
  Future<void> _openCandidates() async {
    final s = _s;
    final list = await ref
        .read(chatProvider.notifier)
        .moderatorCandidates(widget.country);
    if (!mounted) return;
    if (list.isEmpty) {
      showChatSnack(context, s.moderationCandidatesEmpty);
      return;
    }
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                s.moderationCandidatesHint,
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i];
                  return ListTile(
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text('${c['nickname'] ?? c['uid']}'),
                    subtitle: Text('${c['messages'] ?? 0} pesan'),
                    onTap: () => Navigator.pop(ctx, c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final uid = '${picked['uid'] ?? ''}';
    if (uid.isEmpty) return;
    final res = await ref.read(chatProvider.notifier).moderatorSetColleague(
          widget.country,
          uid,
          grant: true,
        );
    if (!mounted) return;
    showChatSnack(
      context,
      _colleagueMessage(res, s),
    );
    await _load();
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
