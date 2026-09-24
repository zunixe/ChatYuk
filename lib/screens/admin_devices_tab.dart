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
import '../providers/admin_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/theme_provider.dart';

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
  String _query = '';
  Timer? _refreshTimer;
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
    _scrollCtrl.addListener(_onScroll);
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
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    final admin = context.read<AdminProvider>();
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      admin.fetchMoreDevices();
    }
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> devices) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return devices;
    return devices.where((d) {
      final nick = '${d['nickname'] ?? ''}'.toLowerCase();
      final model = '${d['model'] ?? ''}'.toLowerCase();
      final brand = '${d['brand'] ?? ''}'.toLowerCase();
      final installId = '${d['install_id'] ?? ''}'.toLowerCase();
      final uid = '${d['user_id'] ?? ''}'.toLowerCase();
      return nick.contains(q) ||
          model.contains(q) ||
          brand.contains(q) ||
          installId.contains(q) ||
          uid.contains(q);
    }).toList();
  }

  /// Grouping per device (install_id). Setiap device punya daftar user yang
  /// pernah login memakainya.
  List<Map<String, dynamic>> _groupByDevice(List<Map<String, dynamic>> rows) {
    final map = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      final key = '${r['install_id'] ?? ''}';
      if (key.isEmpty) continue;
      final group = map.putIfAbsent(key, () {
        return {
          'install_id': key,
          'brand': r['brand'],
          'model': r['model'],
          'os_name': r['os_name'],
          'os_version': r['os_version'],
          'app_version': r['app_version'],
          'ip_address': r['ip_address'],
          'last_seen_at': r['last_seen_at'],
          'users': <Map<String, dynamic>>[],
          '_namesHash': <String>{},
        };
      });
      final users = group['users'] as List<Map<String, dynamic>>;
      final seenNicks = group['_namesHash'] as Set<String>;
      final uid = '${r['user_id'] ?? ''}';
      final nick = '${r['nickname'] ?? ''}';
      final key2 = '$uid|$nick';
      if (!seenNicks.contains(key2)) {
        seenNicks.add(key2);
        users.add({
          'user_id': r['user_id'],
          'nickname': r['nickname'],
          'is_registered': r['is_registered'],
          'last_seen_at': r['last_seen_at'],
        });
      }
      // last seen device = row terbaru
      final seen = (r['last_seen_at'] as String?) ?? '';
      final cur = '${group['last_seen_at'] ?? ''}';
      if (seen.compareTo(cur) > 0) group['last_seen_at'] = r['last_seen_at'];
    }
    final list = map.values.toList();
    list.sort((a, b) =>
        ('${b['last_seen_at'] ?? ''}').compareTo('${a['last_seen_at'] ?? ''}'));
    return list;
  }

  /// Filter device group by query (cocokkan device ATAU salah satu user-nya).
  List<Map<String, dynamic>> _filterGroups(
    List<Map<String, dynamic>> groups,
    String q,
  ) {
    if (q.trim().isEmpty) return groups;
    final lq = q.trim().toLowerCase();
    return groups.where((g) {
      final brand = '${g['brand'] ?? ''}'.toLowerCase();
      final model = '${g['model'] ?? ''}'.toLowerCase();
      final installId = '${g['install_id'] ?? ''}'.toLowerCase();
      if (brand.contains(lq) ||
          model.contains(lq) ||
          installId.contains(lq)) {
        return true;
      }
      final users = (g['users'] as List<Map<String, dynamic>>? ?? const []);
      return users.any((u) {
        final nick = '${u['nickname'] ?? ''}'.toLowerCase();
        final uid = '${u['user_id'] ?? ''}'.toLowerCase();
        return nick.contains(lq) || uid.contains(lq);
      });
    }).toList();
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: s.adminDeviceSearch,
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
          child: admin.devicesLoading && admin.devices.isEmpty
              ? Center(
                  child: CircularProgressIndicator(color: AppTheme.primary),
                )
              : admin.devicesError != null && admin.devices.isEmpty
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
                        s.adminErrTextOf(admin.devicesError!),
                        style: TextStyle(color: AppTheme.danger),
                      ),
                      if (s.adminErrHintOf(admin.devicesError!).isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            s.adminErrHintOf(admin.devicesError!),
                            textAlign: TextAlign.center,
                            style: AppText.bodySmall.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: () => admin.fetchDevices(),
                        child: Text(s.btnRetry),
                      ),
                    ],
                  ),
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
              ? _deviceGroupsView(admin, s)
              : _filtered(admin.devices).isEmpty
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
                        _filtered(admin.devices).length +
                        (admin.devicesHasMore ? 1 : 0),
                    itemBuilder: (_, i) {
                      final filtered = _filtered(admin.devices);
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
  Widget _deviceGroupsView(AdminProvider admin, S s) {
    final groups = _filterGroups(_groupByDevice(admin.devices), _query);
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