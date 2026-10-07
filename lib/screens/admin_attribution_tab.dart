import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;

import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../providers/admin_provider.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/theme_provider.dart';
import '../services/attribution_service.dart';
import '../widgets/admin_error_view.dart';
import '../widgets/app_gesture.dart';
import 'admin_devices/widgets/user_detail_sheet.dart';
import '../providers/riverpod/admin_provider.dart';

/// Admin: tab Atribusi — user datang dari kanal mana (FB/IG/Google/TikTok/
/// referral/organik) + kampanye. Sumber data: Play Install Referrer (kolom
/// attribution_* di user_devices). Klik kanal → daftar user-nya.
class AdminAttributionTab extends ConsumerStatefulWidget {
  const AdminAttributionTab({super.key});

  @override
  ConsumerState<AdminAttributionTab> createState() => _AdminAttributionTabState();
}

class _AdminAttributionTabState extends ConsumerState<AdminAttributionTab> {
  @override
  void initState() {
    super.initState();
    final a = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    Future.microtask(() {
      a.fetchAttribution();
      a.fetchAttributionUsers();
    });
  }

  Color _sourceColor(String key) => switch (key) {
    'facebook' => const Color(0xFF1877F2),
    'instagram' => const Color(0xFFE1306C),
    'google' => const Color(0xFFEA4335),
    'tiktok' => const Color(0xFF010101),
    'referral' => AppTheme.accent,
    'organic' => AppTheme.onlineDark,
    _ => AppTheme.textSecondary,
  };

  IconData _sourceIcon(String key) => switch (key) {
    'facebook' => Icons.facebook,
    'instagram' => Icons.camera_alt,
    'google' => Icons.search,
    'tiktok' => Icons.music_note,
    'referral' => Icons.share,
    'organic' => Icons.eco,
    _ => Icons.help_outline,
  };

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    // GRANULAR: rebuild hanya saat domain ATTRIBUTION berubah.
    ref.watch(adminProvider.select((p) => p.revAttribution));
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    final s = ref.watch(localeProvider).s;
    final summary = admin.attrSummary;
    final sources = _asList(summary?['sources']);
    final campaigns = _asList(summary?['campaigns']);
    final total = (summary?['total'] as num?)?.toInt() ?? 0;

    return Column(
      children: [
        // Header: judul + chip periode.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(s.adminAttributionTab, style: AppText.titleEmphasis),
              ),
              _periodChip(s.adminAttrLast7, 7, admin, s),
              const SizedBox(width: 6),
              _periodChip(s.adminAttrLast30, 30, admin, s),
              const SizedBox(width: 6),
              _periodChip(s.adminAttrAll, 0, admin, s),
            ],
          ),
        ),
        Expanded(
          child: admin.attrLoading && summary == null
              ? Center(child: CircularProgressIndicator(color: AppTheme.primary))
              : admin.attrError != null && summary == null
                  ? AdminErrorView(
                      s: s,
                      error: admin.attrError!,
                      onRetry: () => admin.fetchAttribution(),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        await admin.fetchAttribution();
                        await admin.fetchAttributionUsers(
                          source: admin.attrSource,
                        );
                      },
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          16,
                          12,
                          16,
                          MediaQuery.of(context).padding.bottom + 24,
                        ),
                        children: [
                          Text(
                            s.adminAttrSubtitle,
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _totalCard(s, total),
                          const SizedBox(height: 12),
                          if (sources.isEmpty)
                            _emptyCard(s)
                          else
                            ...sources.map((e) => _sourceTile(s, e, total)),
                          if (campaigns.isNotEmpty) ...[
                            const SizedBox(height: 18),
                            Text(s.adminAttrCampaigns,
                                style: AppText.label.copyWith(
                                  color: AppTheme.textSecondary,
                                )),
                            const SizedBox(height: 6),
                            ...campaigns.take(10).map((c) => _campaignRow(s, c)),
                          ],
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Map<String, dynamic> _asMap(Object? e) =>
      e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{};

  List<Map<String, dynamic>> _asList(Object? e) =>
      (e as List<dynamic>? ?? const []).map(_asMap).toList();

  Widget _periodChip(String label, int days, AdminProvider a, S s) {
    final selected = a.attrDays == days;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => a.fetchAttribution(days: days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : AppTheme.bgInput,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            color: selected ? Colors.white : AppTheme.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _totalCard(S s, int total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.insights, color: AppTheme.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.adminAttrTotalInstalls,
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                  )),
              Text('$total', style: AppText.headline),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(S s) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: [
          Icon(Icons.insights_outlined,
              size: 40, color: AppTheme.textSecondary),
          const SizedBox(height: 10),
          Text(
            s.adminAttrEmpty,
            textAlign: TextAlign.center,
            style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _sourceTile(S s, Map<String, dynamic> e, int total) {
    final key = '${e['source'] ?? 'unknown'}';
    final users = (e['users'] as num?)?.toInt() ?? 0;
    final pct = total > 0 ? (users * 100 / total) : 0.0;
    final color = _sourceColor(key);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: AppGestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openUsers(s, key),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(_sourceIcon(key), color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.adminAttrSourceName(key),
                        style: AppText.bodyStrong),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (pct / 100).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: AppTheme.bgInput,
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$users', style: AppText.bodyStrong),
                  Text('${pct.toStringAsFixed(0)}%',
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campaignRow(S s, Map<String, dynamic> c) {
    final name = '${c['campaign'] ?? ''}';
    final src = '${c['source'] ?? 'unknown'}';
    final users = (c['users'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(_sourceIcon(src), size: 14, color: _sourceColor(src)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: AppText.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text('$users ${s.adminAttrUsers}',
              style: AppText.caption.copyWith(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Future<void> _openUsers(S s, String source) async {
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    await admin.fetchAttributionUsers(source: source);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.bgScreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _AttributionUsersSheet(
        source: source,
        s: s,
        sourceName: s.adminAttrSourceName(source),
        color: _sourceColor(source),
        icon: _sourceIcon(source),
      ),
    );
  }
}

/// Sheet daftar user 1 kanal (pagination + tap → detail user).
class _AttributionUsersSheet extends ConsumerStatefulWidget {
  const _AttributionUsersSheet({
    required this.source,
    required this.s,
    required this.sourceName,
    required this.color,
    required this.icon,
  });

  final String source;
  final S s;
  final String sourceName;
  final Color color;
  final IconData icon;

  @override
  ConsumerState<_AttributionUsersSheet> createState() => _AttributionUsersSheetState();
}

class _AttributionUsersSheetState extends ConsumerState<_AttributionUsersSheet> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(() {
      if (_scrollCtrl.position.pixels >=
          _scrollCtrl.position.maxScrollExtent - 200) {
        final a = ProviderScope.containerOf(context, listen: false).read(adminProvider);
        if (a.attrUsersHasMore) a.loadMoreAttributionUsers();
      }
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _openUser(Map<String, dynamic> u) async {
    final uid = '${u['user_id'] ?? ''}';
    if (uid.isEmpty) return;
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    final detail = await admin.getUserDetail(uid);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.bgScreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => UserDetailSheet(detail: detail, s: widget.s),
    );
  }

  @override
  Widget build(BuildContext context) {
    // GRANULAR: daftar user per kanal bagian dari domain ATTRIBUTION.
    ref.watch(adminProvider.select((p) => p.revAttribution));
    final admin = ProviderScope.containerOf(context, listen: false).read(adminProvider);
    final users = admin.attrUsers;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Icon(widget.icon, color: widget.color, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(widget.sourceName,
                        style: AppText.titleEmphasis),
                  ),
                  Text('${admin.attrUsersTotal} ${widget.s.adminAttrUsers}',
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      )),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                widget.s.adminAttrLinkHint,
                style: AppText.micro.copyWith(color: AppTheme.textSecondary),
              ),
            ),
            Expanded(
              child: admin.attrUsersLoading && users.isEmpty
                  ? Center(
                      child: CircularProgressIndicator(color: AppTheme.primary))
                  : users.isEmpty
                      ? Center(
                          child: Text(
                            widget.s.adminAttrNoResult,
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: EdgeInsets.fromLTRB(
                            12,
                            0,
                            12,
                            MediaQuery.of(context).padding.bottom + 16,
                          ),
                          itemCount: users.length + (admin.attrUsersHasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i >= users.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              );
                            }
                            return _userTile(users[i]);
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  Widget _userTile(Map<String, dynamic> u) {
    final nick = '${u['nickname'] ?? '?'}';
    final email = '${u['email'] ?? ''}';
    final campaign = '${u['utm_campaign'] ?? ''}';
    final isReg = u['is_registered'] == true;
    final at = '${u['attribution_at'] ?? ''}';
    final raw = '${u['referrer_raw'] ?? ''}'.trim();
    final utmSource = '${u['utm_source'] ?? ''}'.trim();
    final utmMedium = '${u['utm_medium'] ?? ''}'.trim();
    final source = '${u['source'] ?? ''}';
    // Terjemahan "link apa yang membawa user ini" — dari service murni.
    final explain = AttributionService.describeReferrer(
      referrerRaw: raw,
      source: source,
      utmSource: utmSource,
      utmMedium: utmMedium,
      utmCampaign: campaign,
    );
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      color: AppTheme.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppTheme.divider),
      ),
      child: AppGestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openUser(u),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: widget.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.person_outline,
                        color: widget.color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nick,
                            style: AppText.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (email.isNotEmpty) email,
                            if (campaign.isNotEmpty) campaign,
                            if (at.length >= 10) at.substring(0, 10),
                          ].join(' · '),
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isReg)
                    Icon(Icons.verified, size: 16, color: AppTheme.primary),
                ],
              ),
              // ── Link yang membawa user (referrer mentah + terjemahan) ──
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.link, size: 14, color: widget.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      explain,
                      style: AppText.caption.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (raw.isNotEmpty || utmSource.isNotEmpty) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.bgInput,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    raw.isNotEmpty
                        ? raw
                        : [
                            if (utmSource.isNotEmpty) 'utm_source=$utmSource',
                            if (utmMedium.isNotEmpty) 'utm_medium=$utmMedium',
                          ].join('&'),
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
