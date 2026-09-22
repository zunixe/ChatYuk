import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import 'admin_deleted/widgets/deleted_card.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../providers/admin_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../core/admin_err.dart';
import '../utils.dart';

/// Admin: arsip user yang sudah dihapus (tab Terhapus).
/// Setiap entry = snapshot user yang pernah ada; klik → detail + riwayat
/// device yang tersisa (device milik hardware, tidak ikut terhapus).
class AdminDeletedTab extends StatefulWidget {
  const AdminDeletedTab({super.key});

  @override
  State<AdminDeletedTab> createState() => _AdminDeletedTabState();
}

class _AdminDeletedTabState extends State<AdminDeletedTab>
    with WidgetsBindingObserver {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _query = '';
  /// Filter: 'all' | 'deleted' | 'pending'.
  String _filter = 'all';
  Timer? _refreshTimer;
  final Set<String> _selectedUids = {};
  bool _batchDeleting = false;
  bool get _isSelectionMode => _selectedUids.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => context.read<AdminProvider>().fetchDeleted());
    _startRefreshTimer();
    _scrollCtrl.addListener(_onScroll);
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    // 30 dtk (dulu 15). Hanya refresh halaman-1 diam-diam — jangan reset
    // paginasi yang sedang di-scroll user (dulu tiap 15 dtk buang load-more).
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final p = context.read<AdminProvider>();
      // Lewati polling kalau user sudah load-more (jangan reset paginasi).
      if (p.deleted.length > 100) return;
      p.fetchDeleted();
    });
  }

  // App di-background → stop polling (hemat battery & beban DB);
  // resume → refresh sekarang lalu polling jalan lagi.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    } else if (state == AppLifecycleState.resumed) {
      if (mounted && _refreshTimer == null) {
        context.read<AdminProvider>().fetchDeleted();
        _startRefreshTimer();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

  void _toggleSelect(String uid) {
    if (uid.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() {
      if (_selectedUids.contains(uid)) {
        _selectedUids.remove(uid);
      } else {
        _selectedUids.add(uid);
      }
    });
  }

  void _selectAll(List<Map<String, dynamic>> items) {
    setState(() {
      final allUids = items
          .map((e) => '${e['user_id'] ?? ''}')
          .where((id) => id.isNotEmpty);
      _selectedUids.addAll(allUids);
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedUids.clear();
    });
  }

  /// Blokir aksi tulis saat offline (gagal separuh jalan + membingungkan).
  bool _guardOffline(S s) => guardOfflineCtx(
    context,
    s.adminNeedsConnection,
    (m) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m))),
  );

  Future<void> _deleteSelected(S s, List<Map<String, dynamic>> allItems) async {
    if (_guardOffline(s)) return;
    final selectedItems = allItems
        .where((e) => _selectedUids.contains('${e['user_id'] ?? ''}'))
        .toList();
    if (selectedItems.isEmpty || _batchDeleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(s.adminDeletedBatchDeleteTitle(selectedItems.length)),
        content: Text(s.adminDeletedBatchDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(s.btnDelete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _batchDeleting = true);
    final count =
        await context.read<AdminProvider>().deleteBatchUsers(selectedItems);
    if (!mounted) return;
    setState(() {
      _batchDeleting = false;
      _selectedUids.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(s.adminDeletedBatchDeleteDone(count)),
        backgroundColor: count > 0 ? AppTheme.online : AppTheme.danger,
      ),
    );
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> rows) {
    Iterable<Map<String, dynamic>> out = rows;
    // Filter jenis: arsip terhapus vs anon pending.
    if (_filter == 'deleted') {
      out = out.where((r) => r['pending'] != true);
    } else if (_filter == 'pending') {
      out = out.where((r) => r['pending'] == true);
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return out.toList();
    return out.where((r) {
      final nick = '${r['nickname'] ?? ''}'.toLowerCase();
      final email = '${r['email'] ?? ''}'.toLowerCase();
      final uid = '${r['user_id'] ?? ''}'.toLowerCase();
      return nick.contains(q) || email.contains(q) || uid.contains(q);
    }).toList();
  }

  /// Chip filter kecil dengan jumlah item; aktif = warna primary/oranye.
  Widget _filterChip(
    String label,
    String value,
    int count, {
    bool highlight = false,
  }) {
    final active = _filter == value;
    final base = highlight ? Colors.orange : AppTheme.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => setState(() {
        _filter = value;
        _selectedUids.clear();
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? base.withValues(alpha: 0.18)
              : AppTheme.bgInput,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? base.withValues(alpha: 0.7) : AppTheme.divider,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: AppText.label.copyWith(
            color: active ? base : AppTheme.textSecondary,
          ),
        ),
      ),
    );
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
      case 'pending_anon':
        return s.adminDeletedPendingReason;
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
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isSelectionMode
                ? Container(
                    key: const ValueKey('selection_header'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          tooltip: s.btnCancel,
                          onPressed: _clearSelection,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            s.adminDeletedSelected(_selectedUids.length),
                            style: AppText.titleEmphasis.copyWith(
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.select_all_rounded,
                            color: AppTheme.primary,
                          ),
                          tooltip: s.adminDeletedSelectAll,
                          onPressed: () =>
                              _selectAll(_filtered(admin.deleted)),
                        ),
                        IconButton(
                          icon: _batchDeleting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.danger,
                                  ),
                                )
                              : const Icon(
                                  Icons.delete_rounded,
                                  color: AppTheme.danger,
                                ),
                          tooltip: s.btnDelete,
                          onPressed: _batchDeleting
                              ? null
                              : () =>
                                  _deleteSelected(s, _filtered(admin.deleted)),
                        ),
                      ],
                    ),
                  )
                : Row(
                    key: const ValueKey('normal_header'),
                    children: [
                      Expanded(
                        child: Text(
                          s.adminDeletedTitle,
                          style: AppText.titleEmphasis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.refresh_rounded,
                          color: AppTheme.primary,
                        ),
                        onPressed: () => admin.fetchDeleted(),
                      ),
                    ],
                  ),
          ),
        ),
        // Filter: Semua / Terhapus / Belum dihapus (anon).
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            children: [
              _filterChip(
                s.adminDeletedFilterAll,
                'all',
                admin.deleted.where((r) => r['pending'] != true).length +
                    admin.deleted.where((r) => r['pending'] == true).length,
              ),
              const SizedBox(width: 6),
              _filterChip(
                s.adminDeletedFilterDeleted,
                'deleted',
                admin.deleted.where((r) => r['pending'] != true).length,
              ),
              const SizedBox(width: 6),
              _filterChip(
                s.adminDeletedFilterPending,
                'pending',
                admin.deleted.where((r) => r['pending'] == true).length,
                highlight: true,
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
              : admin.deletedError != null && admin.deleted.isEmpty
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
                      // Kategori ramah (detail exception hanya ke dlog).
                      Text(
                        s.adminErrTextOf(admin.deletedError!),
                        style: TextStyle(color: AppTheme.danger),
                      ),
                      if (s.adminErrHintOf(admin.deletedError!).isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            s.adminErrHintOf(admin.deletedError!),
                            textAlign: TextAlign.center,
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => admin.fetchDeleted(),
                        child: Text(s.btnRetry),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    if (admin.deletedError != null)
                      Container(
                        width: double.infinity,
                        color: AppTheme.danger.withValues(alpha: 0.12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.cloud_off,
                              size: 16,
                              color: AppTheme.danger,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.adminErrStaleBanner,
                                style: AppText.bodySmall.copyWith(
                                  color: AppTheme.danger,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: _filtered(admin.deleted).isEmpty
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
                      final uid = '${d['user_id'] ?? ''}';
                      final isPending = d['pending'] == true;
                      final isSelected = _selectedUids.contains(uid);
                      return DeletedCard(
                        key: ValueKey('del-$uid'),
                        entry: d,
                        s: s,
                        pending: isPending,
                        selected: isSelected,
                        isSelectionMode: _isSelectionMode,
                        reasonLabel: _reasonLabel(s, '${d['reason'] ?? ''}'),
                        onTap: () {
                          if (_isSelectionMode) {
                            _toggleSelect(uid);
                          } else {
                            _showDetail(context, d);
                          }
                        },
                        onLongPress: () => _toggleSelect(uid),
                      );
                    },
                  ),
                ),
                    ),
                  ],
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


class _DeletedDetailSheet extends StatefulWidget {
  final Map<String, dynamic> entry;
  final List<Map<String, dynamic>> devices;
  final S s;
  const _DeletedDetailSheet({
    required this.entry,
    required this.devices,
    required this.s,
  });

  @override
  State<_DeletedDetailSheet> createState() => _DeletedDetailSheetState();
}

class _DeletedDetailSheetState extends State<_DeletedDetailSheet> {
  bool _deleting = false;

  Map<String, dynamic> get entry => widget.entry;
  List<Map<String, dynamic>> get devices => widget.devices;
  S get s => widget.s;

  bool get _isPending => entry['pending'] == true;

  /// Hapus user anon (pending) — membebaskan nickname. Konfirmasi dulu.
  /// Blokir aksi tulis saat offline (gagal separuh jalan + membingungkan).
  bool _guardOffline(S s) => guardOfflineCtx(
    context,
    s.adminNeedsConnection,
    (m) => ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m))),
  );

  Future<void> _deleteAnon() async {
    if (_guardOffline(s)) return;
    final uid = '${entry['user_id'] ?? ''}';
    if (uid.isEmpty || _deleting) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text(s.adminDeletedDeleteTitle),
        content: Text(s.adminDeletedDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(s.btnDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final res = await context.read<AdminProvider>().deleteAnonUser(uid);
    if (!mounted) return;
    setState(() => _deleting = false);

    final err = '${res['error'] ?? ''}';
    final msg = res['ok'] == true
        ? s.adminDeletedDeleteDone
        : err == 'REGISTERED'
        ? s.adminDeletedDeleteRegistered
        : err == 'DUMMY'
        ? s.adminDeletedDeleteDummy
        : s.adminDeletedDeleteFailed;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: res['ok'] == true ? AppTheme.online : AppTheme.danger,
      ),
    );
    if (res['ok'] == true) Navigator.pop(context);
  }

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
                            decoration: _isPending
                                ? null
                                : TextDecoration.lineThrough,
                            decorationColor: AppTheme.textSecondary,
                          ),
                        ),
                        Row(
                          children: [
                            if (_isPending) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  s.adminDeletedPending,
                                  style: AppText.micro.copyWith(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                reasonLabel,
                                style: AppText.caption.copyWith(
                                  color: _isPending
                                      ? Colors.orange
                                      : AppTheme.danger,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
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
            if (_isPending)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.danger,
                    ),
                    onPressed: _deleting ? null : _deleteAnon,
                    icon: _deleting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.person_remove_rounded, size: 18),
                    label: Text(s.adminDeletedDeleteAction),
                  ),
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