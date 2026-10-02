import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';import 'package:provider/provider.dart';
import '../../../providers/location_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/admin_provider.dart';
import '../../../providers/locale_provider.dart';
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
    'location_mocked',
    'mock_reason',
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
    // Buang channel sepenuhnya (bukan hanya unsubscribe) — cegah bocor
    // socket saat kartu peta dibangun ulang berkali-kali.
    final ch = _channel;
    _channel = null;
    if (ch != null) {
      unawaited(Supabase.instance.client.removeChannel(ch));
    }
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
      ..subscribe((status, err) {
        if (err != null) debugPrint('[ADMIN] usermap realtime error: $err');
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
        // Admin melihat SEMUA user (excluded/dummy pun ikut) — dulu baris ini
        // membuang hidden uid sehingga user asli yang ter-exclude device
        // tampak "hilang" dari admin. Sekarang tampil semua; badge 'excluded'
        // ditandai dari data server bila perlu.
        _users = list.toList();
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
            info = await context.read<LocationProvider>().detectByIp(ip);
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
                      if (u['excluded'] == true) ...[
                        SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            s.adminExcludedBadge,
                            style: AppText.micro.copyWith(
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
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
            // Titik GPS terakhir (koordinat presisi) — hanya bila sumbernya
            // GPS asli, agar tidak salah label untuk koordinat hasil IP.
            if (lat != null && lon != null && u['loc_source'] == 'gps') ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    u['location_mocked'] == true
                        ? Icons.gpp_bad
                        : Icons.my_location,
                    size: 14,
                    color: u['location_mocked'] == true
                        ? AppTheme.danger
                        : Colors.teal,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      u['location_mocked'] == true
                          ? '${s.gpsFake}: $lat, $lon'
                          : '${s.gpsLast}: $lat, $lon',
                      style: AppText.caption.copyWith(
                        color: u['location_mocked'] == true
                            ? AppTheme.danger
                            : Colors.teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (u['location_mocked'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 2, left: 18),
                  child: Text(
                    s.fakeReasonLabel('${u['mock_reason'] ?? ''}'),
                    style: AppText.micro.copyWith(color: AppTheme.danger),
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
    final isFake = u['location_mocked'] == true;
    // Fake GPS = merah (prioritas), lalu GPS (hijau) → IP online (ungu) →
    // IP login (oranye).
    final color = isFake
        ? AppTheme.danger
        : isGps
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
            child: isFake
                ? const Icon(
                    Icons.gpp_bad,
                    size: 14,
                    color: Colors.white,
                  )
                : Text(
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
    // Hitungan legenda HARUS sama persis dengan logika warna marker (_marker):
    // Fake (merah) → GPS (hijau) → IP ter-resolve admin (ungu) → IP login
    // (oranye). Kategori eksklusif (else-if) supaya tidak ada user terhitung
    // dobel — dulu `ipLoginCount = withPos - gps - resolved` bisa NEGATIF
    // kalau ada user GPS yang juga ter-resolve.
    final fakeCount = _users
        .where(
          (u) =>
              (u['lat'] as num?) != null &&
              (u['lon'] as num?) != null &&
              u['location_mocked'] == true,
        )
        .length;
    final gpsCount = _users
        .where(
          (u) =>
              (u['lat'] as num?) != null &&
              (u['lon'] as num?) != null &&
              u['location_mocked'] != true &&
              u['loc_source'] == 'gps',
        )
        .length;
    final resolvedCount = _users
        .where(
          (u) =>
              (u['lat'] as num?) != null &&
              (u['lon'] as num?) != null &&
              u['location_mocked'] != true &&
              u['loc_source'] != 'gps' &&
              u['resolved_ip'] == true,
        )
        .length;
    final ipLoginCount = _users
        .where(
          (u) =>
              (u['lat'] as num?) != null &&
              (u['lon'] as num?) != null &&
              u['location_mocked'] != true &&
              u['loc_source'] != 'gps' &&
              u['resolved_ip'] != true,
        )
        .length;
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
                  Icons.fullscreen,
                  size: 20,
                  color: AppTheme.primary,
                ),
                tooltip: s.mapFullscreen,
                visualDensity: VisualDensity.compact,
                onPressed: _loading || _error != null
                    ? null
                    : () => _openFullscreen(s),
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
              if (fakeCount > 0)
                legendChip(AppTheme.danger, s.mapFakeGps, fakeCount),
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
                  : _buildMapLayer(_mapCtrl, noLoc, withPos, s),
            ),
          ),
          SizedBox(height: 10),
          _LegendExplanations(s: s),
        ],
      ),
    );
  }

  /// Satu sumber render peta — dipakai inline (kartu) dan mode layar penuh.
  /// Menyertakan marker, badge "tanpa lokasi", dan hint ketuk-pin. Tiap
  /// pemanggil WAJIB memberi [ctrl] sendiri (MapController tak boleh dipakai
  /// dua FlutterMap sekaligus).
  Widget _buildMapLayer(
    MapController ctrl,
    int noLoc,
    int withPos,
    S s,
  ) {
    return Stack(
      children: [
        FlutterMap(
          mapController: ctrl,
          options: MapOptions(
            initialCenter: LatLng(-2.5489, 118.0149),
            initialZoom: 4,
            minZoom: 2,
            interactionOptions: InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
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
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                _resolving ? s.mapResolving : '$noLoc ${s.mapNoLocation}',
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
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.bgCard.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                s.mapTapHint,
                style: AppText.micro.copyWith(color: AppTheme.textSecondary),
              ),
            ),
          ),
      ],
    );
  }

  /// Buka peta layar penuh di route baru. Memakai MapController terpisah,
  /// di-center pada posisi peta inline saat tombol ditekan (kontinuitas).
  void _openFullscreen(S s) {
    MapCamera? cam;
    try {
      cam = _mapCtrl.camera;
    } catch (_) {
      // Kamera belum siap (peta belum di-render) — biarkan default.
    }
    final withPos = _users
        .where((u) => (u['lat'] as num?) != null && (u['lon'] as num?) != null)
        .length;
    final noLoc = _users.length - withPos;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenMapPage(
          users: _users,
          resolving: _resolving,
          noLoc: noLoc,
          withPos: withPos,
          initialCenter: cam?.center,
          initialZoom: cam?.zoom,
          markerBuilder: _marker,
          detailBuilder: _showDetail,
        ),
      ),
    );
  }
}

/// Penjelasan tiap warna titik peta (GPS / IP / IP online) + catatan
/// prioritas GPS. Ditampilkan di bawah peta admin supaya admin paham
/// bedanya sebelum mengambil kesimpulan dari titik yang tampak "aneh".
class _LegendExplanations extends StatelessWidget {
  const _LegendExplanations({required this.s});
  final S s;

  @override
  Widget build(BuildContext context) {
    Widget row(Color color, String label, String desc) {
      return Padding(
        padding: EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: EdgeInsets.only(top: 4),
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: AppText.micro.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w400,
                  ),
                  children: [
                    TextSpan(
                      text: '$label · ',
                      style: AppText.micro.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(text: desc),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.info_outline, size: 14, color: AppTheme.textSecondary),
            SizedBox(width: 6),
            Text(
              s.mapLegendTitle,
              style: AppText.caption.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        row(Colors.green, s.mapSourceGps, s.mapLegendGpsDesc),
        row(Colors.orange, s.mapSourceIp, s.mapLegendIpDesc),
        row(Colors.deepPurple, s.mapSourceResolved, s.mapLegendResolvedDesc),
        row(AppTheme.danger, s.mapFakeGps, s.mapFakeGpsDesc),
        Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(
            s.mapLegendNote,
            style: AppText.micro.copyWith(
              color: AppTheme.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

/// Halaman peta user layar penuh (route baru). Memakai MapController SENDIRI
/// (controller tak boleh dipakai dua FlutterMap sekaligus) — di-center pada
/// posisi peta inline saat dibuka supaya transisi terasa mulus. Data user
/// dioper sebagai snapshot; sumber tetap kartu (realtime berjalan di sana).
class _FullscreenMapPage extends StatefulWidget {
  const _FullscreenMapPage({
    required this.users,
    required this.resolving,
    required this.noLoc,
    required this.withPos,
    required this.markerBuilder,
    required this.detailBuilder,
    this.initialCenter,
    this.initialZoom,
  });

  final List<Map<String, dynamic>> users;
  final bool resolving;
  final int noLoc;
  final int withPos;
  final LatLng? initialCenter;
  final double? initialZoom;
  final Marker? Function(Map<String, dynamic>, S) markerBuilder;
  final void Function(Map<String, dynamic>, Color, S) detailBuilder;

  @override
  State<_FullscreenMapPage> createState() => _FullscreenMapPageState();
}

class _FullscreenMapPageState extends State<_FullscreenMapPage> {
  final MapController _fsCtrl = MapController();
  // Batas marker sama dengan kartu — cegah beban render berlebih.
  static const _maxMarkers = 300;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final markers = widget.users
        .take(_maxMarkers)
        .map((u) => widget.markerBuilder(u, s))
        .whereType<Marker>()
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(s.mapFullscreenTitle)),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _fsCtrl,
            options: MapOptions(
              initialCenter: widget.initialCenter ?? LatLng(-2.5489, 118.0149),
              initialZoom: widget.initialZoom ?? 4,
              minZoom: 2,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.chatyuk.chatyuk',
              ),
              MarkerLayer(markers: markers),
            ],
          ),
          if (widget.noLoc > 0)
            Positioned(
              left: 12,
              bottom: 12,
              child: _MapBadge(
                text: widget.resolving
                    ? s.mapResolving
                    : '${widget.noLoc} ${s.mapNoLocation}',
              ),
            ),
          if (widget.withPos == 0 && !widget.resolving)
            Positioned(
              left: 12,
              top: 12,
              child: _MapBadge(text: s.mapTapHint),
            ),
        ],
      ),
    );
  }
}

/// Badge kecil di atas peta (tanpa lokasi / hint). Dipakai mode layar penuh.
class _MapBadge extends StatelessWidget {
  const _MapBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bgCard.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 6),
        ],
      ),
      child: Text(
        text,
        style: AppText.micro.copyWith(
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Bar chart registrasi email per hari — filter bulan (12 bulan terakhir).
/// Bottom sheet daftar user yang registrasi email (nama + email + tgl).
