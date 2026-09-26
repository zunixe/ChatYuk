import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../utils.dart';

/// Satu titik rute pergerakan: lat/lon valid + waktu + sumber (gps/ip).
class RoutePoint {
  final double lat;
  final double lon;
  final DateTime? at;
  final String source;
  const RoutePoint({
    required this.lat,
    required this.lon,
    this.at,
    this.source = '',
  });

  LatLng get latLng => LatLng(lat, lon);
}

/// Parse mentah (Map dari RPC riwayat lokasi) → titik valid urut waktu
/// menaik (garis rute = perjalanan kronologis). Baris tanpa koordinat
/// valid dibuang. Murni (tanpa context) supaya bisa di-unit-test.
List<RoutePoint> parseRoutePoints(
  List<Map<String, dynamic>> raw, {
  int cap = 500,
}) {
  final out = <RoutePoint>[];
  for (final m in raw) {
    final lat = double.tryParse('${m['lat'] ?? ''}');
    final lon = double.tryParse('${m['lon'] ?? ''}');
    if (lat == null || lon == null) continue;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;
    DateTime? at;
    final rawAt = '${m['at'] ?? ''}';
    if (rawAt.isNotEmpty) at = DateTime.tryParse(rawAt);
    out.add(
      RoutePoint(lat: lat, lon: lon, at: at, source: '${m['source'] ?? ''}'),
    );
  }
  out.sort((a, b) {
    if (a.at == null && b.at == null) return 0;
    if (a.at == null) return 1;
    if (b.at == null) return -1;
    return a.at!.compareTo(b.at!);
  });
  return out.length > cap ? out.sublist(out.length - cap) : out;
}

/// Kotak pembatas semua titik (untuk fit kamera). Murni (testable).
LatLngBounds routeBounds(List<RoutePoint> pts) {
  var minLat = pts.first.lat;
  var maxLat = pts.first.lat;
  var minLon = pts.first.lon;
  var maxLon = pts.first.lon;
  for (final p in pts.skip(1)) {
    if (p.lat < minLat) minLat = p.lat;
    if (p.lat > maxLat) maxLat = p.lat;
    if (p.lon < minLon) minLon = p.lon;
    if (p.lon > maxLon) maxLon = p.lon;
  }
  // Titik tunggal/duplikat → beri rentang minimum supaya zoom waras.
  if (minLat == maxLat && minLon == maxLon) {
    const d = 0.01;
    return LatLngBounds(
      LatLng(minLat - d, minLon - d),
      LatLng(maxLat + d, maxLon + d),
    );
  }
  return LatLngBounds(LatLng(minLat, minLon), LatLng(maxLat, maxLon));
}

/// Layar peta rute pergerakan user (admin only): garis perjalanan
/// kronologis + penanda awal/akhir + titik langsiran.
class LocationRouteMapScreen extends StatefulWidget {
  final List<RoutePoint> points;
  final String titleName;
  final S s;
  const LocationRouteMapScreen({
    super.key,
    required this.points,
    required this.titleName,
    required this.s,
  });

  @override
  State<LocationRouteMapScreen> createState() => _LocationRouteMapScreenState();
}

class _LocationRouteMapScreenState extends State<LocationRouteMapScreen> {
  final MapController _mapCtrl = MapController();

  String _timeLabel(DateTime? at) {
    if (at == null) return '-';
    return formatRelativeTime(at, isId: widget.s.isId);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final pts = widget.points;
    final bounds = routeBounds(pts);
    final latLngs = [for (final p in pts) p.latLng];
    final gpsCount = pts.where((p) => p.source == 'gps').length;
    // Penanda langsiran direnggangkan bila titik banyak (maks ~40 dot).
    final step = pts.length <= 40 ? 1 : (pts.length / 40).ceil();

    return Scaffold(
      backgroundColor: AppTheme.bgScreen,
      appBar: AppBar(
        title: Text('${s.adminMapRouteTitle} — ${widget.titleName}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _mapCtrl,
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: bounds,
                  padding: const EdgeInsets.all(48),
                ),
                minZoom: 2,
                interactionOptions: const InteractionOptions(
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
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: latLngs,
                      color: AppTheme.primary,
                      strokeWidth: 4,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    // Nomor urut kronologis di tiap titik langsiran —
                    // arah perjalanan kebaca di sepanjang garis.
                    for (var i = 0; i < pts.length; i += step)
                      if (i != 0 && i != pts.length - 1)
                        Marker(
                          point: pts[i].latLng,
                          width: 24,
                          height: 24,
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              '${i + 1}',
                              style: AppText.micro.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    // Awal (hijau, nomor 1) + akhir (merah, nomor N)
                    // selalu tampil.
                    Marker(
                      point: pts.first.latLng,
                      width: 44,
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.green,
                            size: 40,
                          ),
                            Positioned(
                              top: 5,
                              child: Text(
                                '1',
                                style: AppText.label.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (pts.length > 1)
                      Marker(
                        point: pts.last.latLng,
                        width: 44,
                        height: 44,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            const Icon(
                              Icons.location_on,
                              color: Colors.red,
                              size: 40,
                            ),
                            Positioned(
                              top: 5,
                              child: Text(
                                '${pts.length}',
                                style: AppText.label.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: AppTheme.bgCard,
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              10 + MediaQuery.of(context).padding.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.green,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${s.adminMapStart}: ${_timeLabel(pts.first.at)}',
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.location_on,
                      color: Colors.red,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '${s.adminMapEnd}: ${_timeLabel(pts.last.at)}',
                        style: AppText.caption.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.adminMapPoints(pts.length)} · GPS $gpsCount · IP ${pts.length - gpsCount}',
                  style: AppText.caption.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
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
