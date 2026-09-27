import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../core/chat/chat_location.dart';
import '../providers/locale_provider.dart';
import '../services/location_service.dart';

/// Alur lengkap "kirim lokasi" ala WhatsApp: izin → ambil posisi → sheet
/// pilihan (kirim lokasi saat ini / bagikan lokasi live / tempat sekitar).
///
/// Return [ChatLocation] begitu user memilih salah satu opsi; null bila batal
/// ATAU posisi tidak bisa didapat (pesan error via [messenger]).
///
/// Dipakai bersama private & room supaya perilakunya identik.
Future<ChatLocation?> pickChatLocation(
  BuildContext context, {
  required ScaffoldMessengerState messenger,
}) async {
  final s = context.read<LocaleProvider>().s;
  final loc = LocationService();
  // 1. Minta izin (boleh memunculkan dialog sistem).
  final granted = await loc.requestPermission();
  if (!granted) {
    messenger.showSnackBar(SnackBar(content: Text(s.locPermissionDenied)));
    return null;
  }
  // 2. Posisi presisi (GPS) dulu; fallback last-known/IP bila gagal.
  final precise = await loc.precisePosition();
  double? lat = precise?.$1;
  double? lng = precise?.$2;
  int acc = precise?.$3 ?? 0;
  if (lat == null) {
    final quick = await loc.lastKnownPosition();
    if (quick != null) {
      lat = quick.$1;
      lng = quick.$2;
    }
  }
  if (lat == null) {
    final last = await loc.tryDevicePositionForRegister();
    if (last != null) {
      lat = last.$1;
      lng = last.$2;
    }
  }
  if (lat == null || lng == null) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(s.locFetchFailed)));
    }
    return null;
  }
  if (!context.mounted) return null;
  // 3. Sheet pilihan (kirim saat ini / live / tempat sekitar).
  return showLocationPickerSheet(context, lat: lat, lng: lng, accuracyM: acc);
}

/// Sheet pemilih lokasi (ala WhatsApp): peta + daftar opsi.
Future<ChatLocation?> showLocationPickerSheet(
  BuildContext context, {
  required double lat,
  required double lng,
  int accuracyM = 0,
}) {
  return showModalBottomSheet<ChatLocation>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) =>
        _LocationPickerSheet(lat: lat, lng: lng, accuracyM: accuracyM),
  );
}

class _LocationPickerSheet extends StatefulWidget {
  final double lat;
  final double lng;
  final int accuracyM;
  const _LocationPickerSheet({
    required this.lat,
    required this.lng,
    this.accuracyM = 0,
  });

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  late double _lat = widget.lat;
  late double _lng = widget.lng;
  String _address = '';
  List<NearbyPlace> _places = const [];
  bool _loading = true;
  // Pilihan durasi lokasi live (menit): 15 menit / 1 jam / 8 jam.
  static const _liveDurations = <int>[15, 60, 480];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final svc = LocationService();
    final places = await svc.nearbyPlaces(_lat, _lng);
    if (!mounted) return;
    setState(() {
      _places = places;
      _address = places.isNotEmpty ? places.first.address : '';
      _loading = false;
    });
  }

  void _send({
    String place = '',
    bool live = false,
    int minutes = 0,
    double? lat,
    double? lng,
    String? label,
  }) {
    final exp =
        live ? DateTime.now().toUtc().add(Duration(minutes: minutes)) : null;
    Navigator.pop(
      context,
      ChatLocation(
        lat: lat ?? _lat,
        lng: lng ?? _lng,
        label: label ?? _address,
        place: place,
        live: live,
        expiresAt: exp,
        accuracyM: widget.accuracyM,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    final navPad = MediaQuery.of(context).padding.bottom;
    final bottomPad = navPad > 64 ? navPad : 64.0;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.textSecondary.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_rounded,
                  size: 20,
                  color: Colors.green,
                ),
                const SizedBox(width: 8),
                Text(s.locSendTitle, style: AppText.title),
              ],
            ),
          ),
          // Peta mini (klik untuk pindah titik).
          SizedBox(
            height: 180,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(_lat, _lng),
                    initialZoom: 16,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    onTap: (_, point) => setState(() {
                      _lat = point.latitude;
                      _lng = point.longitude;
                    }),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.chatyuk.chatyuk',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(_lat, _lng),
                          width: 40,
                          height: 40,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 40,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (widget.accuracyM > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                s.locAccuracyTo(widget.accuracyM),
                style: AppText.caption.copyWith(color: Colors.green),
              ),
            ),
          // Daftar opsi (scroll bila tempat banyak).
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _tile(
                    icon: Icons.my_location_rounded,
                    color: Colors.blue,
                    title: s.locSendCurrent,
                    subtitle: _address.isNotEmpty ? _address : null,
                    onTap: () => _send(),
                  ),
                  // Bagikan lokasi live — 3 pilihan durasi.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.share_location_rounded,
                          size: 20,
                          color: Colors.deepOrange,
                        ),
                        const SizedBox(width: 12),
                        Text(s.locLiveTitle, style: AppText.bodyStrong),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                    child: Wrap(
                      spacing: 8,
                      children: [
                        for (final m in _liveDurations)
                          ActionChip(
                            label: Text(_humanDuration(m, s)),
                            avatar: const Icon(
                              Icons.schedule_rounded,
                              size: 16,
                            ),
                            onPressed: () =>
                                _send(live: true, minutes: m),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 12),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(
                      s.locNearbyTitle,
                      style: AppText.label.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    for (final p in _places)
                      _tile(
                        icon: p.name == _places.first.name
                            ? Icons.place_rounded
                            : Icons.place_outlined,
                        color: AppTheme.textSecondary,
                        title: p.name,
                        onTap: () => _send(
                          place: p.name,
                          lat: p.lat,
                          lng: p.lng,
                        ),
                      ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s.locSendCancel),
            ),
          ),
        ],
      ),
    );
  }

  String _humanDuration(int minutes, dynamic s) {
    if (minutes < 60) return s.locLiveMin(minutes);
    return s.locLiveHour(minutes ~/ 60);
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: AppText.bodyStrong, maxLines: 1,
          overflow: TextOverflow.ellipsis),
      subtitle: subtitle != null
          ? Text(subtitle, style: AppText.bodySmall, maxLines: 2,
              overflow: TextOverflow.ellipsis)
          : null,
      onTap: onTap,
    );
  }
}
