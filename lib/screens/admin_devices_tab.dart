import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/theme.dart';
import 'admin_devices/widgets/device_group_card.dart';
import 'admin_devices/widgets/device_card.dart';
import 'admin_devices/widgets/device_detail_sheet.dart';
import 'admin_devices/widgets/user_detail_sheet.dart';
import '../config/strings.dart';
import '../config/strings_admin.dart';
import '../widgets/admin_error_view.dart';
import '../providers/admin_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';
import '../main.dart' show resumeWarmup;
import '../admin/admin_grouping.dart';
import '../utils.dart';
import '../core/ui/scroll_pagination.dart';
import '../widgets/search_field.dart';

/// Admin: pelacakan device & user (tab Perangkat).
/// List semua device semua user; klik → detail user (profil + semua device
/// + daftar chat + riwayat lokasi).
class AdminDevicesTab extends StatefulWidget {
  const AdminDevicesTab({super.key});

  @override
  State<AdminDevicesTab> createState() => _AdminDevicesTabState();
}

class _AdminDevicesTabState extends State<AdminDevicesTab>
    with WidgetsBindingObserver {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  ScrollPagination? _pagination;
  String _query = '';
  Timer? _refreshTimer;
  Timer? _searchDebounce;
  bool _byDevice = true;
  // Per-User: daftar user (dari profiles) BER-PAGINASI — termasuk yang TIDAK
  // punya baris user_devices. Dulu muat SEMUA user sekaligus (loop while) →
  // berat/ngelag. Kini 100/halaman, sisipkan saat scroll, total dari server.
  List<Map<String, dynamic>>? _allUsers;
  int _usersTotal = 0;
  bool _usersLoading = false;
  static const int _usersPageSize = 100;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => context.read<AdminProvider>().fetchDevices());
    // 30 dtk (dulu 15). Polling hanya refresh halaman-1 diam-diam; kalau
    // user sudah load-more, LEWATI agar tidak reset paginasi + lompat scroll.
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final admin = context.read<AdminProvider>();
      if (admin.devices.length > 100) return;
      admin.refreshDevicesSilent();
    });
    _pagination = ScrollPagination(
      controller: _scrollCtrl,
      onLoadMore: () {
        if (!mounted) return;
        if (_byDevice) {
          context.read<AdminProvider>().fetchMoreDevices();
        } else {
          _loadAllUsers();
        }
      },
    );
  }

  /// Muat SATU halaman user "Per User" (paginasi 100). Halaman berikutnya
  /// di-append saat scroll (dipanggil dari ScrollPagination). Total dari
  /// server dipakai untuk header + berhenti saat habis.
  Future<void> _loadAllUsers({bool refresh = false}) async {
    if (_usersLoading) return;
    // Sudah termuat semua → tidak ada lagi (kecuali refresh paksa).
    if (!refresh &&
        _allUsers != null &&
        _allUsers!.length >= _usersTotal &&
        _usersTotal > 0) {
      return;
    }
    _usersLoading = true;
    final admin = context.read<AdminProvider>();
    try {
      final offset = refresh ? 0 : (_allUsers?.length ?? 0);
      final res = await admin.listStatsUsers(
        'all',
        limit: _usersPageSize,
        offset: offset,
      );
      final items = (res['items'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _usersTotal = (res['total'] as num?)?.toInt() ?? _usersTotal;
      final base = refresh ? <Map<String, dynamic>>[] : [...?_allUsers];
      _allUsers = _mergeById([...base, ...items]);
    } catch (e) {
      dlog('[ADMIN] loadAllUsers error: $e');
    }
    _usersLoading = false;
    if (mounted) setState(() {});
  }

  /// Buang duplikat by id (jaga urutan pertama).
  List<Map<String, dynamic>> _mergeById(List<Map<String, dynamic>> list) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final e in list) {
      final id = '${e['id'] ?? e['user_id'] ?? ''}';
      if (id.isEmpty || seen.add(id)) out.add(e);
    }
    return out;
  }

  // Cache hasil merge+filter "Per User" — hindari O(n) tiap build.
  List<Map<String, dynamic>>? _mergedCache;
  int _mergedUsersLen = -1;
  int _mergedDevicesLen = -1;
  String _mergedQuery = '\u0000';

  List<Map<String, dynamic>> _mergedUsers(List<Map<String, dynamic>> devices) {
    final all = _allUsers ?? const [];
    // Kunci cache: panjang user, panjang device, query.
    if (_mergedCache != null &&
        _mergedUsersLen == all.length &&
        _mergedDevicesLen == devices.length &&
        _mergedQuery == _query) {
      return _mergedCache!;
    }
    var users = mergeUsersWithDevices(List.of(all), devices);
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      users = users.where((u) {
        final hay = '${u['_nick'] ?? ''} ${u['email'] ?? ''} ${u['city'] ?? ''} '
                '${u['brand'] ?? ''} ${u['model'] ?? ''} ${u['user_id'] ?? ''}'
            .toLowerCase();
        return hay.contains(q);
      }).toList();
    }
    _mergedCache = users;
    _mergedUsersLen = all.length;
    _mergedDevicesLen = devices.length;
    _mergedQuery = _query;
    return users;
  }



  /// App di-background → stop polling.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    } else if (state == AppLifecycleState.resumed && mounted) {
      if (_refreshTimer == null) {
        unawaited(
          resumeWarmup().then((_) {
            if (mounted) context.read<AdminProvider>().refreshDevicesSilent();
          }),
        );
        _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
          if (!mounted) return;
          final admin = context.read<AdminProvider>();
          if (admin.devices.length > 100) return;
          admin.refreshDevicesSilent();
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _pagination?.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Ketik search = debounce 250ms: filter+grouping+sort O(n log n) hanya
  /// jalan setelah user berhenti mengetik, bukan tiap huruf.
  void _onQueryChanged(String v) {
    _query = v;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() {});
    });
  }


  /// Grouping per device (install_id). Setiap device punya daftar user yang
  /// pernah login memakainya.
  List<Map<String, dynamic>> _groupByDevice(List<Map<String, dynamic>> rows) =>
      groupByDevice(rows);

  /// Filter device group by query (cocokkan device ATAU salah satu user-nya).
  List<Map<String, dynamic>> _filterGroups(
    List<Map<String, dynamic>> groups,
    String q,
  ) =>
      filterDeviceGroups(groups, q);

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final admin = context.watch<AdminProvider>();
    final s = context.watch<LocaleProvider>().s;
    // Hitung SEKALI per build: grouping+sort diulang tiap frame dulu.
    // Per-User TIDAK lagi berbasis device rows (lihat `_usersView`).
    final deviceGroups = _filterGroups(_groupByDevice(admin.devices), _query);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(s.adminDeviceTitle, style: AppText.titleEmphasis),
              ),
              // Toggle tampilan: per device / per user (default).
              // Urutan chip: Per Device kiri, Per User kanan (terpilih saat buka).
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: AppTheme.bgInput,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _seg(s.adminDeviceByDevice, _byDevice, () {
                        setState(() => _byDevice = true);
                      }),
                      _seg(s.adminDeviceByUser, !_byDevice, () {
                        setState(() => _byDevice = false);
                        // Muat semua user sekali (termasuk yang tanpa device).
                        if (_allUsers == null) _loadAllUsers();
                      }),
                    ],
                  ),
                ),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: AppTheme.primary),
                onPressed: () => admin.fetchDevices(),
              ),
            ],
          ),
        ),
        SearchField(
          controller: _searchCtrl,
          onChanged: _onQueryChanged,
          hint: s.adminDeviceSearch,
        ),
        Expanded(
          child: admin.devicesLoading && admin.devices.isEmpty
              ? Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : admin.devicesError != null && admin.devices.isEmpty
              ? AdminErrorView(
                  s: s,
                  error: admin.devicesError!,
                  onRetry: () => admin.fetchDevices(),
                )
              : Column(
                  children: [
                    // Data ada tapi refresh gagal → banner, bukan layar error.
                    if (admin.devicesError != null)
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
                      child: _byDevice
                          ? _deviceGroupsView(admin, s, deviceGroups)
                          : _usersView(admin, s),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// Tampilan "Per User": SEMUA user dari `profiles` (termasuk yang tanpa
  /// baris device). Info device di-join dari [deviceRows] bila ada.
  Widget _usersView(AdminProvider admin, S s) {
    final allUsers = _allUsers;
    if (allUsers == null) {
      // Belum termuat → mulai muat + spinner.
      if (!_usersLoading) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _allUsers == null) _loadAllUsers();
        });
      }
      return Center(
        child: CircularProgressIndicator(color: AppTheme.primary),
      );
    }
    // Gabungkan user + device (user tanpa device tetap tampil). Hasil
    // di-CACHE: merge O(n) dulu jalan tiap build → lag saat scroll/ketik.
    // Sekarang hanya dihitung ulang bila list user/device atau query berubah.
    final users = _mergedUsers(admin.devices);
    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_outline,
              size: 48,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              _query.isEmpty ? s.adminDeviceNoData : s.adminDeviceNoResult,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }
    // Footer: total + status muat-halaman-berikut (paginasi 100).
    final hasMore = _usersTotal > 0 && users.length < _usersTotal;
    return RefreshIndicator(
      onRefresh: () async {
        await admin.fetchDevices();
        await _loadAllUsers(refresh: true);
      },
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          MediaQuery.of(context).padding.bottom + 12,
        ),
        // +1 footer (total / memuat).
        itemCount: users.length + 1,
        itemBuilder: (_, i) {
          if (i >= users.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: hasMore
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${users.length}/$_usersTotal',
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        '$_usersTotal ${s.adminDeviceByUser}',
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
              ),
            );
          }
          final u = users[i];
          final onTap = () => _showUserDetail(context, u);
          // Punya device → kartu device biasa (info device lengkap).
          if (u['_hasDevice'] == true) {
            return DeviceCard(device: u, s: s, onTap: onTap);
          }
          // Tanpa device → kartu user ringkas (nickname + "tanpa perangkat").
          return _userOnlyCard(s, u, onTap);
        },
      ),
    );
  }

  /// Kartu user yang TIDAK punya baris device (mis. belum pernah buka app
  /// sejak fitur tracking) — tetap tampil di "Per User".
  Widget _userOnlyCard(S s, Map<String, dynamic> u, VoidCallback onTap) {
    final nick = '${u['_nick'] ?? u['nickname'] ?? '?'}';
    final uid = '${u['user_id'] ?? ''}';
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
                  color: AppTheme.textSecondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.person_outline,
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nick,
                      style: AppText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.adminDeviceNoDevice,
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (uid.isNotEmpty)
                Text(
                  uid.length >= 8 ? uid.substring(0, 8) : uid,
                  style: AppText.micro.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seg(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primary : Colors.transparent,
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

  Future<void> _showUserDetail(BuildContext context, Map<String, dynamic> d) async {
    final admin = context.read<AdminProvider>();
    final s = context.read<LocaleProvider>().s;
    final uid = '${d['user_id'] ?? ''}';
    if (uid.isEmpty) return;
    final detail = await admin.getUserDetail(uid);
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.bgScreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => UserDetailSheet(detail: detail, s: s),
    );
  }

  /// Bottom sheet detail satu device → daftar user yang pernah login.
  Future<void> _showDeviceDetail(
    BuildContext context,
    Map<String, dynamic> group,
  ) async {
    final s = context.read<LocaleProvider>().s;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.bgScreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => DeviceDetailSheet(group: group, s: s, onOpenUser: (u) {
        // Tutup sheet device, buka detail user.
        Navigator.of(ctx).pop();
        _showUserDetail(context, u);
      }),
    );
  }

  /// List per device (grouping install_id) — device + user yang pernah login.
  /// [groups] sudah dihitung sekali di `build` (jangan hitung ulang di sini).
  Widget _deviceGroupsView(
    AdminProvider admin,
    S s,
    List<Map<String, dynamic>> groups,
  ) {
    if (groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.phone_android_outlined,
              size: 48,
              color: AppTheme.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(
              _query.isEmpty ? s.adminDeviceNoData : s.adminDeviceNoResult,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }
    // Sentinel "muat lebih" di akhir: 1) pemicu saat konten PENDEK (tidak
    // bisa di-scroll → ScrollPagination tak pernah menyala), 2) indikator.
    // Tanpa ini, grouping bisa memadatkan 100 baris → list < viewport →
    // sisa device TIDAK PERNAH termuat ("slide bawah ga ngeload").
    final hasMore = admin.devicesHasMore;
    return RefreshIndicator(
      onRefresh: () => admin.fetchDevices(),
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: EdgeInsets.fromLTRB(
          12,
          0,
          12,
          MediaQuery.of(context).padding.bottom + 12,
        ),
        itemCount: groups.length + (hasMore ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= groups.length) return _loadMoreSentinel(admin);
          final g = groups[i];
          return DeviceGroupCard(
            group: g,
            s: s,
            onTap: () => _showDeviceDetail(context, g),
          );
        },
      ),
    );
  }

  /// Item akhir "load more": memicu fetch halaman berikutnya lewat panggilan
  /// post-frame (aman dipanggil saat build), lalu menampilkan spinner.
  Widget _loadMoreSentinel(AdminProvider admin) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) admin.fetchMoreDevices();
    });
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
}