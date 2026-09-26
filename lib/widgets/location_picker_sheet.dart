import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../config/theme.dart';
import '../core/chat/chat_location.dart';
import '../providers/locale_provider.dart';
import '../services/location_service.dart';

/// Alur lengkap "kirim lokasi": izin → ambil posisi → sheet peta.
///
/// Return [ChatLocation] bila user menekan kirim; null bila batal ATAU
/// posisi tidak bisa didapat (pesan error sudah ditampilkan via [messenger]).
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
  // 2. Ambil posisi: last-known (cepat) dulu, lalu fix GPS/network.
  final quick = await loc.lastKnownPosition();
  final pos = quick ?? await loc.tryDevicePositionForRegister();
  if (pos == null) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(s.locFetchFailed)));
    }
    return null;
  }
  if (!context.mounted) return null;
  // 3. Sheet peta — user bisa geser marker sebelum kirim.
  return showLocationPickerSheet(context, lat: pos.$1, lng: pos.$2);
}

/// Sheet pemilih lokasi (ala WhatsApp): peta + marker di titik, tombol kirim.
///
/// Return [ChatLocation] saat user menekan kirim; null bila dibatalkan.
/// Marker bisa digeser (tap peta untuk pindah titik) supaya user bisa
/// koreksi posisi sebelum kirim.
Future<ChatLocation?> showLocationPickerSheet(
  BuildContext context, {
  required double lat,
  required double lng,
}) {
  return showModalBottomSheet<ChatLocation>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _LocationPickerSheet(lat: lat, lng: lng),
  );
}

class _LocationPickerSheet extends StatefulWidget {
  final double lat;
  final double lng;
  const _LocationPickerSheet({required this.lat, required this.lng});

  @override
  State<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<_LocationPickerSheet> {
  late double _lat = widget.lat;
  late double _lng = widget.lng;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    // BUG PERNAH KEJADIAN: padding bawah hanya viewInsets (keyboard) lalu
    // hanya padding.bottom — di HP nav 3-tombol (MIUI), inset yang dilaporkan
    // = 0 sehingga tombol Batal/Lampirkan TERTUTUP nav bar sistem → tap user
    // jatuh ke tombol Back sistem → sheet tertutup null (tidak terkirim).
    // Solusi deterministik: JANGKA MINIMUM 64dp (lebih tinggi dari nav bar
    // ~48dp) + hormati inset bila lebih besar. Jangan mengandalkan
    // MediaQuery saja di sheet ini.
    final navPad = MediaQuery.of(context).padding.bottom;
    final bottomPad = navPad > 64 ? navPad : 64.0;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          // Peta: tinggi tetap supaya sheet stabil. Tap peta → pindah marker.
          SizedBox(
            height: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
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
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('OpenStreetMap contributors'),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              '${_lat.toStringAsFixed(5)}, ${_lng.toStringAsFixed(5)}',
              style: AppText.caption.copyWith(color: AppTheme.textSecondary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(s.locSendCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      ChatLocation(lat: _lat, lng: _lng),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text(s.locAttach),
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
