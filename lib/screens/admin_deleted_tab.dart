import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import 'admin_deleted/widgets/deleted_card.dart';
import 'admin_deleted/widgets/deleted_detail_sheet.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../widgets/admin_error_view.dart';
import '../providers/admin_provider.dart';
import '../providers/locale_provider.dart';
import '../main.dart' show resumeWarmup;
import '../providers/theme_provider.dart';
import '../utils.dart';
import '../core/ui/scroll_pagination.dart';
import '../widgets/search_field.dart';
import '../widgets/filter_chip_pill.dart';
import '../core/admin_err.dart';

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
  ScrollPagination? _pagination;
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
    _pagination = ScrollPagination(
      controller: _scrollCtrl,
      onLoadMore: () {
        if (!mounted) return;
        context.read<AdminProvider>().fetchMoreDeleted();
      },
    );
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
        unawaited(
          resumeWarmup().then((_) {
            if (mounted) context.read<AdminProvider>().fetchDeleted();
          }),
        );
        _startRefreshTimer();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    _pagination?.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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
    if (_query.trim().isEmpty) return out.toList();
    return out
        .where((r) => matchesQuery(r, _query, const [
              'nickname',
              'email',
              'user_id',
            ]))
        .toList();
  }

  /// Chip filter kecil dengan jumlah item; aktif = warna primary/oranye.
  Widget _filterChip(
    String label,
    String value,
    int count, {
    bool highlight = false,
  }) {
    return FilterChipPill(
      label: label,
      count: count,
      active: _filter == value,
      color: highlight ? Colors.orange : AppTheme.primary,
      onTap: () => setState(() {
        _filter = value;
        _selectedUids.clear();
      }),
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
    // GRANULAR: rebuild hanya saat domain DELETED berubah.
    context.select<AdminProvider, int>((p) => p.revDeleted);
    final admin = context.read<AdminProvider>();
    final s = context.watch<LocaleProvider>().s;
    // Hitung sekali per build — dulu `_filtered()` dipanggil di dalam
    // `itemBuilder` sehingga daftar difilter ulang untuk SETIAP baris (O(n²)
    // pada 100+ item) dan hasilnya tidak stabil antar frame.
    final filtered = _filtered(admin.deleted);

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
        // Filter: Semua / Terhapus / Belum dihapus (anon) — SATU baris
        // horizontal (bisa di-scroll bila layar sempit), bukan Wrap yang
        // menjatuhkan chip terakhir ke baris kedua.
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _filterChip(
                  s.adminDeletedFilterAll,
                  'all',
                  admin.deletedTotal,
                ),
                const SizedBox(width: 6),
                _filterChip(
                  s.adminDeletedFilterDeleted,
                  'deleted',
                  admin.deletedArchivedTotal,
                ),
                const SizedBox(width: 6),
                _filterChip(
                  s.adminDeletedFilterPending,
                  'pending',
                  admin.deletedPendingTotal,
                  highlight: true,
                ),
              ],
            ),
          ),
        ),
        SearchField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          hint: s.adminDeletedSearch,
        ),
        Expanded(
          child: admin.deletedLoading && admin.deleted.isEmpty
              ? Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : admin.deletedError != null && admin.deleted.isEmpty
              ? AdminErrorView(
                  s: s,
                  error: admin.deletedError!,
                  onRetry: () => admin.fetchDeleted(),
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
                      child: filtered.isEmpty
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
                        filtered.length +
                        (admin.deletedHasMore ? 1 : 0),
                    itemBuilder: (_, i) {
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
    final uid = '${d['user_id'] ?? ''}';
    List<Map<String, dynamic>> devices = const [];
    List<Map<String, dynamic>> locations = const [];
    if (nick.isNotEmpty) {
      devices = await admin.getDeletedDeviceHistory(nick);
    }
    if (uid.isNotEmpty) {
      locations = await admin.getDeletedLocationHistory(uid);
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
      builder: (ctx) => DeletedDetailSheet(
        entry: d,
        devices: devices,
        locations: locations,
        s: s,
      ),
    );
  }
}