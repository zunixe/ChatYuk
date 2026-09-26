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
        context.read<AdminProvider>().fetchMoreDevices();
      },
    );
  }

  /// App di-background → stop polling.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    } else if (state == AppLifecycleState.resumed && mounted) {
      if (_refreshTimer == null) {
        context.read<AdminProvider>().refreshDevicesSilent();
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


  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> devices) {
    if (_query.trim().isEmpty) return devices;
    return devices
        .where((d) => matchesQuery(d, _query, const [
              'nickname',
              'model',
              'brand',
              'install_id',
              'user_id',
            ]))
        .toList();
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
    // Hitung SEKALI per build: dulu `_filtered()` dipanggil di itemCount +
    // di dalam itemBuilder per baris (O(n²) saat scroll), dan grouping+sort
    // diulang tiap frame. Sekarang hasilnya dipakai ulang di bawah.
    final filteredDevices = _filtered(admin.devices);
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
              : filteredDevices.isEmpty
              ? Center(
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
                        _query.isEmpty
                            ? s.adminDeviceNoData
                            : s.adminDeviceNoResult,
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => admin.fetchDevices(),
                  child: ListView.builder(
                    controller: _scrollCtrl,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      0,
                      12,
                      MediaQuery.of(context).padding.bottom + 12,
                    ),
                    itemCount:
                        filteredDevices.length +
                        (admin.devicesHasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= filteredDevices.length) {
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
                      final d = filteredDevices[i];
                      return DeviceCard(
                        device: d,
                        s: s,
                        onTap: () => _showUserDetail(context, d),
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
        itemCount: groups.length,
        itemBuilder: (_, i) {
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
}