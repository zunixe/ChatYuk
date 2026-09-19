import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/locale_provider.dart';
import '../../../services/avatar_service.dart';
import '../../../services/geo_service.dart';
import '../../../utils.dart';

class AdminUserMapCard extends StatefulWidget {
  const AdminUserMapCard();
  @override
  State<AdminUserMapCard> createState() => AdminUserMapCardState();
}

class AdminUserMapCardState extends State<AdminUserMapCard> {
  final MapController _mapCtrl = MapController();
  final Map<String, GeoInfo?> _ipCache = {};
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  bool _resolving = false;
  String? _error;
  int _resolveFail = 0;
  RealtimeChannel? _channel;
  Timer? _notifyDebounce;
  bool _live = false;

  // Batas resolve IP per load (hindari rate-limit provider gratis).
  static const _maxIpResolve = 40;
  // Batas marker yang dirender (users_all diurutkan last_seen desc).
  static const _maxMarkers = 300;

  // Kolom profiles yang dipantau realtime dan dipakai peta.
  static const _trackedFields = [
    'nickname',
    'gender',
    'age',
    'country',
    'city',
    'ip_address',
    'status',
    'is_registered',
    'last_seen',
    'lat',
    'lon',
    'loc_source',
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _notifyDebounce?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  /// Realtime: pantau perubahan profiles (login user baru = INSERT,
  /// update lokasi/last_seen = UPDATE) supaya peta selalu segar
  /// tanpa refresh manual.
  void _subscribeRealtime() {
    _channel = Supabase.instance.client.channel('admin-user-map')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'profiles',
        callback: _onProfileChange,
      )
      ..subscribe((status, _) {
        if (!mounted) return;
        setState(() {
          _live = status == RealtimeSubscribeStatus.subscribed;
        });
      });
  }

  void _onProfileChange(PostgresChangePayload payload) {
    final rec = payload.newRecord;
    if (rec.isEmpty) {
      // DELETE: id hanya ada di oldRecord (replica identity default).
      final oldId = '${payload.oldRecord['id'] ?? ''}';
      if (oldId.isNotEmpty) {
        _users.removeWhere((u) => '${u['id'] ?? ''}' == oldId);
      }
      _notify();
      return;
    }
    final id = '${rec['id'] ?? ''}';
    // Dummy + user device-ter-exclude jangan masuk peta via realtime
    // (jalur load sudah bersih dari server — users_all terfilter).
    if (id.isNotEmpty && mounted) {
      try {
        if (context.read<AdminProvider>().isHiddenUid(id)) {
          _users.removeWhere((u) => '${u['id'] ?? ''}' == id);
          _notify();
          return;
        }
      } catch (_) {}
    }
    Map<String, dynamic>? existing;
    for (final u in _users) {
      if (id.isNotEmpty && '${u['id'] ?? ''}' == id) {
        existing = u;
        break;
      }
    }
    // Fallback RPC lama tanpa kolom id: cocokkan nickname + ip.
    if (existing == null && id.isNotEmpty) {
      for (final u in _users) {
        if (u['id'] == null &&
            '${u['nickname'] ?? ''}' == '${rec['nickname'] ?? ''}' &&
            '${u['ip_address'] ?? ''}' == '${rec['ip_address'] ?? ''}') {
          existing = u;
          break;
        }
      }
    }
    if (existing == null) {
      final entry = <String, dynamic>{'id': id};
      for (final f in _trackedFields) {
        entry[f] = rec[f];
      }
      _users.insert(0, entry);
    } else {
      for (final f in _trackedFields) {
        if (rec.containsKey(f)) existing[f] = rec[f];
      }
      // Koordinat asli dari server menimpa hasil resolve client.
      if (rec['lat'] != null && rec['lon'] != null) {
        existing.remove('resolved_ip');
      }
      // Naikkan ke depan list (urut last_seen desc) agar tidak
      // tergeser batas _maxMarkers.
      _users.remove(existing);
      _users.insert(0, existing);
    }
    _notify();
    // User baru tanpa koordinat tapi punya IP → resolve agar pin muncul.
    if (rec['lat'] == null &&
        rec['lon'] == null &&
        '${rec['ip_address'] ?? ''}'.isNotEmpty) {
      _resolveIps();
    }
  }

  /// Gabungkan event realtime yang berdekatan jadi satu rebuild peta.
  void _notify() {
    if (!mounted) return;
    _notifyDebounce?.cancel();
    _notifyDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final admin = context.read<AdminProvider>();
      await admin.fetchHiddenUids();
      final detail = await admin.fetchStatsDetail();
      final list =
          (detail['users_all'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      if (!mounted) return;
      setState(() {
        // Sabuk pengaman ganda: buang hidden uid yang lolos (data cache lama
        // tanpa 'id' tetap tampil — '' tidak pernah ada di hidden set).
        _users = list
            .where((u) => !admin.isHiddenUid('${u['id'] ?? ''}'))
            .toList();
        _loading = false;
      });
      await _resolveIps();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  /// Resolve IP untuk user yang belum punya lat/lon (login tanpa GPS).
  /// Paralel per batch (6) + setState per batch — bukan per user —
  /// supaya peta tidak rebuild 40× dan loading tidak menunggu sequential.
  Future<void> _resolveIps() async {
    if (_resolving) return;
    _resolving = true;
    if (mounted) setState(() {});
    final targets = _users
        .where((u) {
          final lat = (u['lat'] as num?)?.toDouble();
          final lon = (u['lon'] as num?)?.toDouble();
          final ip = '${u['ip_address'] ?? ''}';
          return (lat == null || lon == null) && ip.isNotEmpty;
        })
        .take(_maxIpResolve)
        .toList();
    var fail = 0;
    const batchSize = 6;
    for (var i = 0; i < targets.length; i += batchSize) {
      final batch = targets.skip(i).take(batchSize).toList();
      await Future.wait(
        batch.map((u) async {
          final ip = '${u['ip_address'] ?? ''}';
          GeoInfo? info;
          if (_ipCache.containsKey(ip)) {
            info = _ipCache[ip];
          } else {
            info = await GeoService().detectByIp(ip);
            _ipCache[ip] = info;
          }
          if (info?.lat != null && info?.lon != null) {
            u['lat'] = info!.lat;
            u['lon'] = info.lon;
            u['resolved_ip'] = true;
          } else {
            fail++;
          }
        }),
      );
      if (mounted) setState(() {});
    }
    if (mounted) {
      setState(() {
        _resolving = false;
        _resolveFail = fail;
      });
    }
  }

  void _showDetail(Map<String, dynamic> u, Color color, S s) {
    final lat = (u['lat'] as num?)?.toDouble();
    final lon = (u['lon'] as num?)?.toDouble();
    final city = '${u['city'] ?? ''}';
    final country = '${u['country'] ?? ''}';
    final name = '${u['nickname'] ?? '?'}';
    final lastSeen = u['last_seen'] != null
        ? formatRelativeTime(
            DateTime.tryParse('${u['last_seen']}') ?? DateTime.now(),
            isId: s.isId,
          )
        : '';
    final source = u['resolved_ip'] == true
        ? s.mapSourceResolved
        : u['loc_source'] == 'gps'
        ? s.mapSourceGps
        : s.mapSourceIp;
    final mapsUrl = lat != null && lon != null
        ? 'https://www.google.com/maps/search/?api=1&query=$lat,$lon'
        : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent([city, country].where((e) => e.isNotEmpty).join(', '))}';

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgScreen,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: AppText.titleEmphasis.copyWith(color: color),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: AppText.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (lastSeen.isNotEmpty)
                        Text(
                          s.adminLastUpdate + ' ' + lastSeen,
                          style: AppText.caption.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    source,
                    style: AppText.label.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if ((u['age'] ?? 0) > 0 ||
                city.isNotEmpty ||
                country.isNotEmpty) ...[
              SizedBox(height: 10),
              Text(
                [
                  if ((u['age'] ?? 0) > 0)
                    '${u['age']} ${u['gender'] == 'female'
                        ? 'Perempuan'
                        : u['gender'] == 'male'
                        ? 'Laki-laki'
                        : ''}',
                  if (city.isNotEmpty) city,
                  if (country.isNotEmpty) country,
                ].where((e) => e.isNotEmpty).join(' · '),
                style: AppText.bodySmall.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(mapsUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.map_outlined, size: 16),
                label: Text(s.mapOpenMaps),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Marker? _marker(Map<String, dynamic> u, S s) {
    final lat = (u['lat'] as num?)?.toDouble();
    final lon = (u['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    final isGps = u['loc_source'] == 'gps';
    final isResolved = u['resolved_ip'] == true;
    final color = isGps
        ? Colors.green
        : isResolved
        ? Colors.deepPurple
        : Colors.orange;
    final name = '${u['nickname'] ?? '?'}';
    return Marker(
      point: LatLng(lat, lon),
      width: 26,
      height: 26,
      child: GestureDetector(
        onTap: () => _showDetail(u, color, s),
        child: Container(
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 4,
              ),
            ],
          ),
          child: Center(
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: AppText.caption.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final withPos = _users
        .where((u) => (u['lat'] as num?) != null && (u['lon'] as num?) != null)
        .length;
    final gpsCount = _users.where((u) => u['loc_source'] == 'gps').length;
    final resolvedCount = _users.where((u) => u['resolved_ip'] == true).length;
    final ipLoginCount = withPos - gpsCount - resolvedCount;
    final noLoc = _users.length - withPos;

    Widget legendChip(Color color, String label, int count) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            SizedBox(width: 4),
            Text(
              '$label $count',
              style: AppText.micro.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.map_outlined, size: 16, color: Colors.teal),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.adminMapTitle,
                      style: AppText.caption.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      s.adminMapSubtitle,
                      style: AppText.micro.copyWith(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (_live)
                Container(
                  margin: EdgeInsets.only(right: 6),
                  padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 4),
                      Text(
                        s.mapLive,
                        style: AppText.micro.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_resolving)
                Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              IconButton(
                icon: Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppTheme.primary,
                ),
                visualDensity: VisualDensity.compact,
                onPressed: _loading ? null : _load,
              ),
            ],
          ),
          SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              legendChip(Colors.green, s.mapSourceGps, gpsCount),
              legendChip(Colors.orange, s.mapSourceIp, ipLoginCount),
              legendChip(Colors.deepPurple, s.mapSourceResolved, resolvedCount),
              if (_resolveFail > 0)
                legendChip(Colors.redAccent, s.mapResolveFailed, _resolveFail),
            ],
          ),
          SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 280,
              child: _loading
                  ? Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Text(
                        _error!,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.danger,
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapCtrl,
                          options: MapOptions(
                            initialCenter: LatLng(-2.5489, 118.0149),
                            initialZoom: 4,
                            minZoom: 2,
                            interactionOptions: InteractionOptions(
                              flags:
                                  InteractiveFlag.all & ~InteractiveFlag.rotate,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.chatyuk.chatyuk',
                            ),
                            MarkerLayer(
                              markers: _users
                                  .take(_maxMarkers)
                                  .map((u) => _marker(u, s))
                                  .whereType<Marker>()
                                  .toList(),
                            ),
                          ],
                        ),
                        if (noLoc > 0)
                          Positioned(
                            left: 8,
                            bottom: 8,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.bgCard.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Text(
                                _resolving
                                    ? s.mapResolving
                                    : '$noLoc ${s.mapNoLocation}',
                                style: AppText.micro.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        if (withPos == 0 && !_resolving)
                          Positioned(
                            left: 8,
                            top: 8,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.bgCard.withValues(alpha: 0.92),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                s.mapTapHint,
                                style: AppText.micro.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bar chart registrasi email per hari — filter bulan (12 bulan terakhir).
/// Bottom sheet daftar user yang registrasi email (nama + email + tgl).
class AdminRegistrationsSheet extends StatefulWidget {
  const AdminRegistrationsSheet();
  @override
  State<AdminRegistrationsSheet> createState() => AdminRegistrationsSheetState();
}

class AdminRegistrationsSheetState extends State<AdminRegistrationsSheet> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => context.read<AdminProvider>().fetchRegistrations(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final admin = context.watch<AdminProvider>();
    final list = admin.registrations;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(s.adminRegListTitle, style: AppText.title),
            ),
            Expanded(
              child: admin.registrationsLoading && list.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : list.isEmpty
                  ? Center(
                      child: Text(
                        s.adminNoUsers,
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: EdgeInsets.fromLTRB(
                        16,
                        0,
                        16,
                        MediaQuery.of(context).padding.bottom + 24,
                      ),
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final r = list[i];
                        final nick = r['nickname'] ?? '?';
                        final email = r['email'] ?? '-';
                        final created = r['created_at'] != null
                            ? formatRelativeTime(
                                DateTime.tryParse(r['created_at']) ??
                                    DateTime.now(),
                                isId: s.isId,
                              )
                            : '';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color:
                                      AppTheme.primary.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '$nick'.isNotEmpty
                                        ? '$nick'[0].toUpperCase()
                                        : '?',
                                    style: AppText.bodyStrong.copyWith(
                                      color: AppTheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(nick, style: AppText.bodyStrong),
                                    Text(
                                      email,
                                      style: AppText.caption.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                created,
                                style: AppText.micro.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Card penggunaan data Supabase: pie chart DB vs gambar + kuota +
/// pertumbuhan per hari/minggu/bulan.
class AdminStorageUsageCard extends StatefulWidget {
  const AdminStorageUsageCard();
  @override
  State<AdminStorageUsageCard> createState() => AdminStorageUsageCardState();
}

class AdminStorageUsageCardState extends State<AdminStorageUsageCard> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      final a = context.read<AdminProvider>();
      a.fetchStorageStats();
      a.fetchCfUsage();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final admin = context.watch<AdminProvider>();
    final st = admin.storageStats;
    final loading = admin.storageStatsLoading && st == null;

    final dbBytes = ((st?['db_bytes'] ?? 0) as num).toInt();
    final storBytes = ((st?['storage_bytes'] ?? 0) as num).toInt();
    final files = ((st?['storage_files'] ?? 0) as num).toInt();
    final total = ((st?['total_bytes'] ?? 0) as num).toInt();
    final quotaDb = ((st?['quota_db_bytes'] ?? 1) as num).toInt();
    final quotaStor = ((st?['quota_storage_bytes'] ?? 1) as num).toInt();

    final growth = (st?['growth'] as Map<String, dynamic>?) ?? const {};

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.donut_small_rounded,
                        size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Text(s.adminStorageTitle, style: AppText.bodyStrong),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // Pie chart DB vs Storage.
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CustomPaint(
                        painter: AdminUsagePiePainter(dbBytes, storBytes),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: Builder(builder: (_) {
                      final dbPct = quotaDb > 0 ? dbBytes / quotaDb : 0.0;
                      final storPct =
                          quotaStor > 0 ? storBytes / quotaStor : 0.0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _legendRow(AppTheme.primary, s.adminStorageDb,
                              formatBytes(dbBytes)),
                          _legendRow(AppTheme.accent, s.adminStorageImages,
                              formatBytes(storBytes)),
                          const Divider(height: 18),
                          _kv(s.adminStorageTotal, formatBytes(total)),
                          _kv('${s.adminStorageDb} (${s.adminQuotaLabel})',
                              '${formatBytes(dbBytes)} / ${formatBytes(quotaDb)}'),
                          _progress(dbPct.clamp(0.0, 1.0), AppTheme.primary),
                          _kv('${s.adminStorageImages} (${s.adminQuotaLabel})',
                              '${formatBytes(storBytes)} / ${formatBytes(quotaStor)}'),
                          _progress(storPct.clamp(0.0, 1.0), AppTheme.accent),
                          _kv(s.adminStorageFiles, '$files'),
                        ],
                      );
                    })),
                  ],
                ),
                const SizedBox(height: 16),
                Text(s.adminStorageGrowth, style: AppText.bodyStrong),
                const SizedBox(height: 6),
                _growthTable(s, growth),
                const SizedBox(height: 16),
                Text(s.adminCfTitle, style: AppText.bodyStrong),
                const SizedBox(height: 8),
                _cfSection(admin, s),
              ],
            ),
    );
  }

Widget _cfSection(AdminProvider admin, S s) {
    final cf = admin.cfUsage;
    if (cf == null) {
      return Text(
        '...',
        style: AppText.caption.copyWith(color: AppTheme.textSecondary),
      );
    }
    if (cf['configured'] != true) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.bgInput.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          s.adminCfNotConfigured,
          style: AppText.caption.copyWith(color: AppTheme.textSecondary),
        ),
      );
    }
    if (cf['error'] != null) {
      return Text(
        '${cf['error']}',
        style: AppText.caption.copyWith(color: AppTheme.danger),
      );
    }
    final monthBytes = ((cf['month_bytes'] ?? 0) as num).toInt();
    final weekBytes = ((cf['week_bytes'] ?? 0) as num).toInt();
    final dayBytes = ((cf['day_bytes'] ?? 0) as num).toInt();
    final quota = ((cf['quota_bytes'] ?? 1) as num).toInt();
    final pct = quota > 0 ? (monthBytes / quota).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${s.adminCfMonth}: ${formatBytes(monthBytes)}',
                style: AppText.bodySmall,
              ),
            ),
            Text(
              '${s.adminQuotaLabel}: ${formatBytes(quota)}',
              style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct <= 0 ? null : pct,
              minHeight: 5,
              backgroundColor: AppTheme.divider.withValues(alpha: 0.4),
              valueColor: AlwaysStoppedAnimation<Color>(
                pct > 0.85 ? AppTheme.danger : AppTheme.primary,
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '${s.adminGrowthDay}: ${formatBytes(dayBytes)}',
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                '${s.adminGrowthWeek}: ${formatBytes(weekBytes)}',
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ),
            Expanded(
              child: Text(
                '${(pct * 100).toStringAsFixed(1)}%',
                style: AppText.caption.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _legendRow(Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label, style: AppText.bodySmall),
          ),
          Text(value, style: AppText.bodySmall.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(k, style: AppText.bodySmall.copyWith(color: AppTheme.textSecondary)),
          ),
          Text(v, style: AppText.bodySmall),
        ],
      ),
    );
  }

  Widget _progress(double pct, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(
          value: pct <= 0 ? null : pct,
          minHeight: 5,
          backgroundColor: AppTheme.divider.withValues(alpha: 0.4),
          valueColor: AlwaysStoppedAnimation<Color>(
            pct > 0.85 ? AppTheme.danger : color,
          ),
        ),
      ),
    );
  }

  Widget _growthTable(S s, Map<String, dynamic> growth) {
    final rows = [
      (
        s.adminGrowthDay,
        growth['day'] ?? const {},
      ),
      (s.adminGrowthWeek, growth['week'] ?? const {}),
      (s.adminGrowthMonth, growth['month'] ?? const {}),
    ];
    Widget cellHeader(String t, {bool count = false}) => Expanded(
          child: Align(
            alignment: count ? Alignment.centerRight : Alignment.centerLeft,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                t,
                maxLines: 1,
                style: AppText.micro.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
    String fmtCell(Map m, String key, {bool count = false}) {
      final v = (m[key] ?? 0) as num;
      return count ? '$v' : (v <= 0 ? '-' : formatBytes(v));
    }
    Widget cellValue(String t, {bool strong = false}) => Expanded(
          child: Text(
            t,
            maxLines: 1,
            style: strong
                ? AppText.caption.copyWith(fontWeight: FontWeight.w700)
                : AppText.micro.copyWith(color: AppTheme.textSecondary),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bgInput.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(children: [
            const SizedBox(width: 70),
            cellHeader(s.adminGrowthMessages),
            cellHeader(s.adminGrowthSignals),
            cellHeader(s.adminGrowthImages),
            cellHeader(s.adminGrowthRegistrations, count: true),
          ]),
          const SizedBox(height: 6),
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 58,
                    child: Text(r.$1, style: AppText.caption),
                  ),
                  cellValue(fmtCell(r.$2 as Map, 'messages')),
                  cellValue(fmtCell(r.$2 as Map, 'signals')),
                  cellValue(fmtCell(r.$2 as Map, 'storage')),
                  cellValue(
                    fmtCell(r.$2 as Map, 'registrations', count: true),
                    strong: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Pie chart sederhana DB vs Storage (CustomPaint, tanpa dependency).
class AdminUsagePiePainter extends CustomPainter {
  final int dbBytes;
  final int storBytes;
  AdminUsagePiePainter(this.dbBytes, this.storBytes);

  @override
  void paint(Canvas canvas, Size size) {
    final total = dbBytes + storBytes;
    final paint = Paint()..style = PaintingStyle.fill;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Ring luar (track).
    paint.color = AppTheme.divider.withValues(alpha: 0.35);
    canvas.drawArc(rect.deflate(2), -pi / 2, pi * 2, true, paint);

    if (total > 0) {
      final dbFrac = dbBytes / total;
      paint.color = AppTheme.primary;
      canvas.drawArc(rect.deflate(8), -pi / 2, pi * 2 * dbFrac, true, paint);
      paint.color = AppTheme.accent;
      canvas.drawArc(rect.deflate(8), -pi / 2 + pi * 2 * dbFrac,
          pi * 2 * (1 - dbFrac), true, paint);
    }
  }

  @override
  bool shouldRepaint(AdminUsagePiePainter oldDelegate) =>
      oldDelegate.dbBytes != dbBytes || oldDelegate.storBytes != storBytes;
}

class AdminRegistrationsChartCard extends StatefulWidget {
  const AdminRegistrationsChartCard();
  @override
  State<AdminRegistrationsChartCard> createState() =>
      AdminRegistrationsChartCardState();
}

class AdminRegistrationsChartCardState extends State<AdminRegistrationsChartCard> {
  static const _barW = 18.0;
  static const _chartH = 110.0;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _fetch();
  }

  void _fetch() {
    context.read<AdminProvider>().fetchRegistrationsDaily(
      _month.year,
      _month.month,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final admin = context.watch<AdminProvider>();
    final data = admin.regDaily;
    final now = DateTime.now();
    final months = [
      for (var i = 0; i < 12; i++) DateTime(now.year, now.month - i),
    ];
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final maxCount = data.isEmpty
        ? 1
        : data.values.reduce((a, b) => a > b ? a : b);
    final total = data.values.fold<int>(0, (a, b) => a + b);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showRegistrationsSheet(context),
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.bar_chart_rounded,
                size: 16,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Text(s.adminRegTitle, style: AppText.bodyStrong),
              const Spacer(),
              DropdownButton<DateTime>(
                value: _month,
                isDense: true,
                underline: const SizedBox.shrink(),
                iconSize: 18,
                style: AppText.bodySmall.copyWith(color: AppTheme.textPrimary),
                items: [
                  for (final m in months)
                    DropdownMenuItem(
                      value: m,
                      child: Text('${s.monthShort[m.month - 1]} ${m.year}'),
                    ),
                ],
                onChanged: (m) {
                  if (m == null) return;
                  setState(() => _month = m);
                  _fetch();
                },
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${s.adminRegPerDay} · ${s.adminRegTotal}: $total',
            style: AppText.caption.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 10),
          if (admin.regLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else if (data.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  s.adminRegEmpty,
                  style: AppText.bodySmall.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var d = 1; d <= days; d++)
                    _bar(d, data[d] ?? 0, maxCount, s),
                ],
              ),
            ),
        ],
      ),
      ),
    );
  }

  Widget _bar(int day, int count, int maxCount, S s) {
    final h = count == 0
        ? 2.0
        : (count / maxCount * _chartH).clamp(3.0, _chartH);
    final showLabel = day == 1 || day % 5 == 0 || day == 31;
    return Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            count > 0 ? '$count' : '',
            style: AppText.micro.copyWith(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 2),
          Container(
            width: _barW,
            height: h,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  AppTheme.primary.withValues(alpha: 0.45),
                  AppTheme.primary,
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 12,
            child: showLabel
                ? Text(
                    '$day',
                    style: AppText.micro.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  /// Bottom sheet daftar user yang registrasi (email + tanggal).
  Future<void> _showRegistrationsSheet(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.bgScreen,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => const AdminRegistrationsSheet(),
    );
  }
}

/// Avatar lazy per-baris di list Users admin (Ringkasan): fetch avatar
/// hanya saat baris tampil (sheet memakai ListView.builder) + cache
/// RAM/disk via AvatarB64Service. Tap → zoom besar. Tanpa foto → inisial.
class AdminAvatarCircle extends StatefulWidget {
  final String uid;
  final String name;
  final Color color;
  const AdminAvatarCircle({
    required this.uid,
    required this.name,
    required this.color,
  });

  @override
  State<AdminAvatarCircle> createState() => AdminAvatarCircleState();
}

class AdminAvatarCircleState extends State<AdminAvatarCircle> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.uid.isEmpty) return;
    try {
      final b64 = await AvatarB64Service.instance.get(widget.uid);
      if (!mounted || b64.isEmpty) return;
      setState(() => _bytes = base64Decode(b64));
    } catch (_) {}
  }

  void _zoom() {
    final bytes = _bytes;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: bytes != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      )
                    : CircleAvatar(
                        radius: 90,
                        backgroundColor: widget.color,
                        child: Text(
                          widget.name.isNotEmpty
                              ? widget.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppGlyph.xl,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _zoom,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _bytes != null
              ? Colors.transparent
              : widget.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _bytes != null
              ? Image.memory(_bytes!, fit: BoxFit.cover)
              : Center(
                  child: Text(
                    widget.name.isNotEmpty
                        ? widget.name[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: AppGlyph.avatarInitial(34),
                      color: widget.color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
