import 'dart:async';

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
