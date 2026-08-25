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
import 'admin_chat_view_screen.dart';

/// Admin: pelacakan device & user (tab Perangkat).
/// List semua device semua user; klik → detail user (profil + semua device
/// + daftar chat + riwayat lokasi).
class AdminDevicesTab extends StatefulWidget {
  const AdminDevicesTab({super.key});

  @override
  State<AdminDevicesTab> createState() => _AdminDevicesTabState();
}

class _AdminDevicesTabState extends State<AdminDevicesTab> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  String _query = '';
  Timer? _refreshTimer;
  bool _byDevice = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => context.read<AdminProvider>().fetchDevices());
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      context.read<AdminProvider>().refreshDevicesSilent();
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
              // Toggle tampilan: per user (default) / per device.
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppTheme.bgInput,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _seg(s.adminDeviceByUser, !_byDevice, () {
                      setState(() => _byDevice = false);
                    }),
                    _seg(s.adminDeviceByDevice, _byDevice, () {
                      setState(() => _byDevice = true);
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
                      Text(
                        admin.devicesError!,
                        style: TextStyle(color: AppTheme.danger),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: () => admin.fetchDevices(),
                        child: Text(s.btnRetry),
                      ),
                    ],
                  ),
                )
              : _byDevice
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
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
                      return _DeviceCard(
                        device: d,
                        s: s,
                        onTap: () => _showUserDetail(context, d),
                      );
                    },
                  ),
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
      builder: (ctx) => _UserDetailSheet(detail: detail, s: s),
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
      builder: (ctx) => _DeviceDetailSheet(group: group, s: s, onOpenUser: (u) {
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
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        itemCount: groups.length,
        itemBuilder: (_, i) {
          final g = groups[i];
          return _DeviceGroupCard(
            group: g,
            s: s,
            onTap: () => _showDeviceDetail(context, g),
          );
        },
      ),
    );
  }
}

class _DeviceGroupCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final S s;
  final VoidCallback onTap;
  const _DeviceGroupCard({
    required this.group,
    required this.s,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = '${group['brand'] ?? ''}';
    final model = '${group['model'] ?? ''}';
    final osName = '${group['os_name'] ?? ''}';
    final osVersion = '${group['os_version'] ?? ''}';
    final users = (group['users'] as List<Map<String, dynamic>>? ?? const []);
    final lastSeen = group['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${group['last_seen_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';
    final deviceLabel = [
      if (brand.isNotEmpty) brand,
      if (model.isNotEmpty) model,
    ].join(' ').trim();
    final osLabel = [
      if (osName.isNotEmpty) osName,
      if (osVersion.isNotEmpty) osVersion,
    ].join(' ').trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      color: AppTheme.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: AppTheme.primary.withValues(alpha: 0.35)),
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
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.phone_android,
                  color: AppTheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceLabel.isEmpty ? 'Unknown device' : deviceLabel,
                      style: AppText.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (osLabel.isNotEmpty)
                      Text(
                        osLabel,
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    // Nama user yang pernah login di device ini.
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final u in users)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: (u['is_registered'] == true
                                      ? AppTheme.primary
                                      : AppTheme.accent)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${u['nickname'] ?? '?'}',
                              style: AppText.micro.copyWith(
                                color: u['is_registered'] == true
                                    ? AppTheme.primary
                                    : AppTheme.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
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
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${users.length} ${s.adminDeviceCount}',
                    style: AppText.caption.copyWith(
                      color: AppTheme.textSecondary,
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

class _DeviceCard extends StatelessWidget {
  final Map<String, dynamic> device;
  final S s;
  final VoidCallback onTap;
  const _DeviceCard({
    required this.device,
    required this.s,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final nick = '${device['nickname'] ?? '?'}';
    final uid = '${device['user_id'] ?? ''}';
    final brand = '${device['brand'] ?? ''}';
    final model = '${device['model'] ?? ''}';
    final osName = '${device['os_name'] ?? ''}';
    final osVersion = '${device['os_version'] ?? ''}';
    final appVer = '${device['app_version'] ?? ''}';
    final ip = '${device['ip_address'] ?? ''}';
    final active = device['is_active'] == true;
    final registered = device['is_registered'] == true;
    final lastSeen = device['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${device['last_seen_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';

    final deviceLabel = [
      if (brand.isNotEmpty) brand,
      if (model.isNotEmpty) model,
    ].join(' ').trim();
    final osLabel = [
      if (osName.isNotEmpty) osName,
      if (osVersion.isNotEmpty) osVersion,
    ].join(' ').trim();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      color: AppTheme.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: active
              ? AppTheme.primary.withValues(alpha: 0.35)
              : AppTheme.divider,
        ),
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
                child: Icon(
                  Icons.phone_android,
                  color: registered ? AppTheme.primary : AppTheme.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            nick,
                            style: AppText.bodyStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: (active ? Colors.green : AppTheme.textSecondary)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            active ? s.adminDeviceActive : s.adminDeviceInactive,
                            style: AppText.micro.copyWith(
                              color: active
                                  ? Colors.green
                                  : AppTheme.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (deviceLabel.isNotEmpty)
                      Text(
                        deviceLabel,
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Row(
                      children: [
                        if (osLabel.isNotEmpty) ...[
                          Icon(
                            Icons.phone_iphone,
                            size: 12,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              osLabel,
                              style: AppText.micro.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (ip.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.lan_outlined,
                            size: 12,
                            color: AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            ip,
                            style: AppText.micro.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ],
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
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${uid.length >= 8 ? uid.substring(0, 8) : uid}',
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                      fontFeatures: const [],
                    ),
                  ),
                  if (appVer.isNotEmpty)
                    Text(
                      'v$appVer',
                      style: AppText.micro.copyWith(
                        color: AppTheme.textSecondary,
                      ),
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

class _DeviceDetailSheet extends StatelessWidget {
  final Map<String, dynamic> group;
  final S s;
  final void Function(Map<String, dynamic> user) onOpenUser;
  const _DeviceDetailSheet({
    required this.group,
    required this.s,
    required this.onOpenUser,
  });

  @override
  Widget build(BuildContext context) {
    final brand = '${group['brand'] ?? ''}';
    final model = '${group['model'] ?? ''}';
    final osName = '${group['os_name'] ?? ''}';
    final osVersion = '${group['os_version'] ?? ''}';
    final appVer = '${group['app_version'] ?? ''}';
    final ip = '${group['ip_address'] ?? ''}';
    final installId = '${group['install_id'] ?? ''}';
    final lastSeen = group['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${group['last_seen_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';
    final users = (group['users'] as List<Map<String, dynamic>>? ?? const []);
    final deviceLabel = [
      if (brand.isNotEmpty) brand,
      if (model.isNotEmpty) model,
    ].join(' ').trim();
    final osLabel = [
      if (osName.isNotEmpty) osName,
      if (osVersion.isNotEmpty) osVersion,
    ].join(' ').trim();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
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
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.phone_android,
                      color: AppTheme.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deviceLabel.isEmpty ? 'Unknown device' : deviceLabel,
                          style: AppText.title,
                        ),
                        if (osLabel.isNotEmpty)
                          Text(
                            osLabel,
                            style: AppText.caption.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  if (appVer.isNotEmpty)
                    _kv('${s.adminDeviceModel}', deviceLabel),
                  if (osLabel.isNotEmpty) _kv('${s.adminDeviceOs}', osLabel),
                  if (appVer.isNotEmpty) _kv('App', 'v$appVer'),
                  if (ip.isNotEmpty) _kv('${s.adminDeviceIp}', ip),
                  _kv('${s.adminDeviceInstallId}', installId),
                  if (lastSeen.isNotEmpty)
                    _kv('${s.adminDeviceLastSeen}', lastSeen),
                  const SizedBox(height: 12),

                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      s.adminDeviceUsersUsed,
                      style: AppText.label.copyWith(color: AppTheme.primary),
                    ),
                  ),
                  if (users.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        s.adminDeviceNoUsers,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    for (final u in users) _userChip(u),
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
            width: 110,
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

  Widget _userChip(Map<String, dynamic> u) {
    final nick = '${u['nickname'] ?? '?'}';
    final registered = u['is_registered'] == true;
    final lastSeen = u['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${u['last_seen_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: AppTheme.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onOpenUser(u),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: (registered ? AppTheme.primary : AppTheme.accent)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
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
                    Text(nick, style: AppText.bodyStrong),
                    Text(
                      [
                        registered ? s.adminDeviceRegistered : s.adminDeviceAnon,
                        if (lastSeen.isNotEmpty)
                          '${s.adminDeviceLastSeen}: $lastSeen',
                      ].join(' · '),
                      style: AppText.micro.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: AppTheme.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserDetailSheet extends StatefulWidget {
  final Map<String, dynamic> detail;
  final S s;
  const _UserDetailSheet({required this.detail, required this.s});

  @override
  State<_UserDetailSheet> createState() => _UserDetailSheetState();
}

class _UserDetailSheetState extends State<_UserDetailSheet> {
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final profile =
        (widget.detail['profile'] as Map<String, dynamic>?) ?? const {};
    final devices =
        (widget.detail['devices'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? const [];
    final chats =
        (widget.detail['chats'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? const [];
    final locHist =
        (widget.detail['location_history'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? const [];

    final nick = '${profile['nickname'] ?? '?'}';
    final uid = '${profile['user_id'] ?? ''}';
    final email = '${profile['email'] ?? ''}';
    final registered = profile['is_registered'] == true;
    final status = '${profile['status'] ?? ''}';
    final ageVal = profile['age'];
    final gender = '${profile['gender'] ?? ''}';
    final city = '${profile['city'] ?? ''}';
    final country = '${profile['country'] ?? ''}';
    final points = '${profile['points'] ?? 0}';
    final ip = '${profile['ip_address'] ?? ''}';
    final isDummy = profile['is_dummy'] == true;

    final lastLogin = profile['login_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${profile['login_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '-';
    final created = profile['created_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${profile['created_at']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '-';

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
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
                        Text(nick, style: AppText.title),
                        Text(
                          [
                            registered ? s.adminDeviceRegistered : s.adminDeviceAnon,
                            if (isDummy) 'Dummy',
                          ].join(' · '),
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: s.adminDeviceCopyId,
                    icon: Icon(Icons.copy_rounded, size: 18, color: AppTheme.primary),
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
                  _section(s.adminDeviceProfile),
                  _kv(s.adminDeviceUserid, uid),
                  if (email.isNotEmpty) _kv(s.adminDeviceEmail, email),
                  _kv(s.adminDeviceStatus, status),
                  _kv(s.adminDeviceLastLogin, lastLogin),
                  _kv(s.adminDeviceCreated, created),
                  if (ageVal is int && ageVal > 0) _kv(s.adminDeviceAge, '$ageVal'),
                  if (gender.isNotEmpty) _kv(s.adminDeviceGender, gender),
                  if (city.isNotEmpty) _kv(s.adminDeviceCity, '$city, $country'),
                  _kv(s.adminDevicePoints, points),
                  if (ip.isNotEmpty) _kv(s.adminDeviceIp, ip),
                  const SizedBox(height: 12),

                  _section(s.adminDeviceDevices),
                  if (devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        s.adminDeviceNoDevices,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    for (final d in devices) _deviceTile(d),
                  const SizedBox(height: 12),

                  _section(s.adminDeviceChats),
                  if (chats.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        s.adminDeviceNoChats,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    )
                  else
                    for (final c in chats) _chatTile(c, uid),
                  const SizedBox(height: 12),

                  if (locHist.isNotEmpty) ...[
                    _section(s.adminDeviceLocation),
                    for (final l in locHist.take(20)) _locTile(l),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(title, style: AppText.label.copyWith(color: AppTheme.primary)),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          Expanded(
            child: Text(v, style: AppText.bodySmall),
          ),
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
    final active = d['is_active'] == true;
    final lastSeen = d['last_seen_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${d['last_seen_at']}') ?? DateTime.now(),
            isId: widget.s.isId,
          )
        : '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active
              ? AppTheme.primary.withValues(alpha: 0.35)
              : AppTheme.divider,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.phone_android,
            size: 16,
            color: active ? AppTheme.primary : AppTheme.textSecondary,
          ),
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
                if (lastSeen.isNotEmpty)
                  Text(
                    '${widget.s.adminDeviceLastSeen}: $lastSeen',
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: (active ? Colors.green : AppTheme.textSecondary)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              active
                  ? widget.s.adminDeviceActive
                  : widget.s.adminDeviceInactive,
              style: AppText.micro.copyWith(
                color: active ? Colors.green : AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatTile(Map<String, dynamic> c, String selfUid) {
    final names = (c['participant_names'] as Map<dynamic, dynamic>?) ?? {};
    final participants = (c['participants'] as List<dynamic>?) ?? const [];
    String otherName = '';
    for (final p in participants) {
      if ('$p' != selfUid) {
        otherName = '${names['$p'] ?? ''}';
        break;
      }
    }
    if (otherName.isEmpty) {
      otherName = names.values
          .where((e) => e != null && '$e'.isNotEmpty)
          .map((e) => '$e')
          .join(', ');
    }
    final lastMsg = '${c['last_message'] ?? ''}'.trim();
    final lastAt = c['last_message_at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${c['last_message_at']}') ?? DateTime.now(),
            isId: widget.s.isId,
          )
        : '';
    final chatId = '${c['chat_id'] ?? ''}';
    final orderUids = participants.map((p) => '$p').toList();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      color: AppTheme.bgCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.divider),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: chatId.isEmpty
            ? null
            : () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdminChatViewScreen(
                      chatId: chatId,
                      chatLabel: otherName.isEmpty ? 'Chat' : otherName,
                      participantOrder: orderUids,
                    ),
                  ),
                );
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 16, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      otherName.isEmpty ? 'Chat' : otherName,
                      style: AppText.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (lastMsg.isNotEmpty)
                      Text(
                        lastMsg,
                        style: AppText.micro.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (lastAt.isNotEmpty)
                Text(
                  lastAt,
                  style: AppText.micro.copyWith(color: AppTheme.textSecondary),
                ),
              Icon(Icons.chevron_right, size: 18, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _locTile(Map<String, dynamic> l) {
    final lat = '${l['lat'] ?? ''}';
    final lon = '${l['lon'] ?? ''}';
    final source = '${l['source'] ?? ''}';
    final at = l['at'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${l['at']}') ?? DateTime.now(),
            isId: widget.s.isId,
          )
        : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.place_outlined, size: 14, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(
            '$lat, $lon',
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const Spacer(),
          if (source.isNotEmpty)
            Text(
              source,
              style: AppText.micro.copyWith(color: AppTheme.textSecondary),
            ),
          if (at.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              at,
              style: AppText.micro.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}