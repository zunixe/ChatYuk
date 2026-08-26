import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../providers/admin_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../utils.dart';

/// Admin: arsip user yang sudah dihapus (tab Terhapus).
/// Setiap entry = snapshot user yang pernah ada; klik → detail + riwayat
/// device yang tersisa (device milik hardware, tidak ikut terhapus).
class AdminDeletedTab extends StatefulWidget {
  const AdminDeletedTab({super.key});

  @override
  State<AdminDeletedTab> createState() => _AdminDeletedTabState();
}

class _AdminDeletedTabState extends State<AdminDeletedTab> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _query = '';
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<AdminProvider>().fetchDeleted());
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      context.read<AdminProvider>().fetchDeleted();
    });
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final admin = context.read<AdminProvider>();
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      admin.fetchMoreDeleted();
    }
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> rows) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return rows;
    return rows.where((r) {
      final nick = '${r['nickname'] ?? ''}'.toLowerCase();
      final email = '${r['email'] ?? ''}'.toLowerCase();
      final uid = '${r['user_id'] ?? ''}'.toLowerCase();
      return nick.contains(q) || email.contains(q) || uid.contains(q);
    }).toList();
  }

  String _reasonLabel(S s, String reason) {
    switch (reason) {
      case 'stale_cleanup':
        return s.adminDeletedStale;
      case 'nickname_claim':
        return s.adminDeletedClaim;
      case 'admin_delete':
        return s.adminDeletedAdmin;
      case 'dummy_delete':
        return s.adminDeletedDummy;
      default:
        return reason;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final admin = context.watch<AdminProvider>();
    final s = context.watch<LocaleProvider>().s;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(s.adminDeletedTitle, style: AppText.titleEmphasis),
              ),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: AppTheme.primary),
                onPressed: () => admin.fetchDeleted(),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: s.adminDeletedSearch,
              prefixIcon: Icon(
                Icons.search_rounded,
                color: AppTheme.textSecondary,
                size: 20,
              ),
              isDense: true,
              filled: true,
              fillColor: AppTheme.bgInput,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: admin.deletedLoading && admin.deleted.isEmpty
              ? Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : admin.deletedError != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: AppTheme.danger,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        admin.deletedError!,
                        style: TextStyle(color: AppTheme.danger),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => admin.fetchDeleted(),
                        child: Text(s.btnRetry),
                      ),
                    ],
                  ),
                )
              : _filtered(admin.deleted).isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 48,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _query.isEmpty
                            ? s.adminDeletedNoData
                            : s.adminDeletedNoResult,
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => admin.fetchDeleted(),
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      0,
                      12,
                      MediaQuery.of(context).padding.bottom + 12,
                    ),
                    itemCount:
                        _filtered(admin.deleted).length +
                        (admin.deletedHasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      final filtered = _filtered(admin.deleted);
                      if (i >= filtered.length) {
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
                      final d = filtered[i];
                      return _DeletedCard(
                        entry: d,
                        s: s,
                        reasonLabel: _reasonLabel(s, '${d['reason'] ?? ''}'),
                        onTap: () => _showDetail(context, d),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _showDetail(
    BuildContext context,
    Map<String, dynamic> d,
  ) async {
    final admin = context.read<AdminProvider>();
    final s = context.read<LocaleProvider>().s;
    final nick = '${d['nickname'] ?? ''}';
    List<Map<String, dynamic>> devices = const [];
    if (nick.isNotEmpty) {
      devices = await admin.getDeletedDeviceHistory(nick);
    }
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.bgScreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => _DeletedDetailSheet(entry: d, devices: devices, s: s),
    );
  }
}

class _DeletedCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final S s;
  final String reasonLabel;
  final VoidCallback onTap;
  const _DeletedCard({
    required this.entry,
    required this.s,
    required this.reasonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nick = '${entry['nickname'] ?? '?'}';
    final email = '${entry['email'] ?? ''}';
    final registered = entry['is_registered'] == true;
    final deletedAt = entry['deleted_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${entry['deleted_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';
    final lastSeen = entry['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${entry['last_seen_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      color: AppTheme.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppTheme.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (registered ? AppTheme.primary : AppTheme.accent)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    nick.isNotEmpty ? nick[0].toUpperCase() : '?',
                    style: AppText.bodyStrong.copyWith(
                      color: registered ? AppTheme.primary : AppTheme.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nick,
                      style: AppText.bodyStrong.copyWith(
                        decoration: TextDecoration.lineThrough,
                        decorationColor: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      [
                        reasonLabel,
                        if (lastSeen.isNotEmpty)
                          '${s.adminDeviceLastSeen}: $lastSeen',
                      ].join(' · '),
                      style: AppText.micro.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (deletedAt.isNotEmpty)
                    Text(
                      deletedAt,
                      style: AppText.micro.copyWith(
                        color: AppTheme.danger,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeletedDetailSheet extends StatelessWidget {
  final Map<String, dynamic> entry;
  final List<Map<String, dynamic>> devices;
  final S s;
  const _DeletedDetailSheet({
    required this.entry,
    required this.devices,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final nick = '${entry['nickname'] ?? '?'}';
    final uid = '${entry['user_id'] ?? ''}';
    final email = '${entry['email'] ?? ''}';
    final registered = entry['is_registered'] == true;
    final reason = '${entry['reason'] ?? ''}';
    final claimedBy = '${entry['claimed_by'] ?? ''}';
    final claimedNick = '${entry['claimed_nick'] ?? ''}';
    final brand = '${entry['brand'] ?? ''}';
    final model = '${entry['model'] ?? ''}';
    final ip = '${entry['ip_address'] ?? ''}';
    final lastSeen = entry['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${entry['last_seen_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '-';
    final deletedAt = entry['deleted_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${entry['deleted_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '-';

    final reasonLabel = switch (reason) {
      'stale_cleanup' => s.adminDeletedStale,
      'nickname_claim' => s.adminDeletedClaim,
      'admin_delete' => s.adminDeletedAdmin,
      'dummy_delete' => s.adminDeletedDummy,
      _ => reason,
    };

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: (registered ? AppTheme.primary : AppTheme.accent)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        nick.isNotEmpty ? nick[0].toUpperCase() : '?',
                        style: AppText.bodyStrong.copyWith(
                          color: registered ? AppTheme.primary : AppTheme.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nick,
                          style: AppText.title.copyWith(
                            decoration: TextDecoration.lineThrough,
                            decorationColor: AppTheme.textSecondary,
                          ),
                        ),
                        Text(
                          reasonLabel,
                          style: AppText.caption.copyWith(
                            color: AppTheme.danger,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: s.adminDeviceCopyId,
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: uid));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(s.adminDeviceCopied),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _kv(s.adminDeletedUid, uid),
                  if (email.isNotEmpty) _kv(s.adminDeviceEmail, email),
                  _kv(s.adminDeviceRegistered,
                      registered ? s.adminDeviceRegistered : s.adminDeviceAnon),
                  _kv(s.adminDeletedReason, reasonLabel),
                  _kv(s.adminDeletedAt, deletedAt),
                  _kv(s.adminDeviceLastSeen, lastSeen),
                  if (brand.isNotEmpty || model.isNotEmpty)
                    _kv(s.adminDeviceModel,
                        [brand, model].where((e) => e.isNotEmpty).join(' ')),
                  if (ip.isNotEmpty) _kv(s.adminDeviceIp, ip),
                  if (reason == 'nickname_claim') ...[
                    if (claimedBy.isNotEmpty)
                      _kv(s.adminDeletedClaimedBy, claimedBy),
                    if (claimedNick.isNotEmpty)
                      _kv(s.adminDeletedNewNick, claimedNick),
                  ],
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      s.adminDeletedDeviceHistory,
                      style: AppText.label.copyWith(color: AppTheme.primary),
                    ),
                  ),
                  if (devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        s.adminDeletedNoDevice,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    for (final d in devices) _deviceTile(d),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              k,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          Expanded(child: Text(v, style: AppText.bodySmall)),
        ],
      ),
    );
  }

  Widget _deviceTile(Map<String, dynamic> d) {
    final brand = '${d['brand'] ?? ''}';
    final model = '${d['model'] ?? ''}';
    final os = [
      '${d['os_name'] ?? ''}',
      '${d['os_version'] ?? ''}',
    ].where((e) => e.isNotEmpty).join(' ');
    final ip = '${d['ip_address'] ?? ''}';
    final lastSeen = d['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${d['last_seen_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Icon(Icons.phone_android, size: 16, color: AppTheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [brand, model].where((e) => e.isNotEmpty).join(' '),
                  style: AppText.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (os.isNotEmpty)
                  Text(
                    os,
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                if (ip.isNotEmpty)
                  Text(
                    ip,
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                if (lastSeen.isNotEmpty)
                  Text(
                    '${s.adminDeviceLastSeen}: $lastSeen',
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}