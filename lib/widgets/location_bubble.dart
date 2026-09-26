import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/theme.dart';
import '../core/chat/chat_location.dart';

/// Bubble pesan LOKASI (ala WhatsApp): peta mini + label, tap → Google Maps.
///
/// Peta hanya-pandang (tanpa interaksi) supaya tidak merebut gesture scroll
/// chat. Bila tile gagal dimuat (offline), latar abu + ikon tetap tampil —
/// tombol buka Google Maps tetap bisa ditekan.
class LocationBubble extends StatelessWidget {
  final ChatLocation location;
  /// Lebar kartu (default 220). Pakai `double.infinity` di preview composer.
  final double width;
  /// Tinggi peta (default 160).
  final double height;
  /// Boleh di-geser/zoom? Bubble chat = false (agar tidak merebut scroll);
  /// preview composer = true (user bisa koreksi titik sebelum kirim).
  final bool interactive;
  const LocationBubble({
    super.key,
    required this.location,
    this.width = 220,
    this.height = 160,
    this.interactive = false,
  });

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse(location.mapsUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(location.lat, location.lng),
                    initialZoom: 15,
                    interactionOptions: InteractionOptions(
                      flags: interactive
                          ? InteractiveFlag.all & ~InteractiveFlag.rotate
                          : InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.chatyuk.chatyuk',
                      // Offline/gagal → latar netral, jangan kotak merah.
                      errorTileCallback: (_, _, _) {},
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(location.lat, location.lng),
                          width: 36,
                          height: 36,
                          alignment: Alignment.topCenter,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 36,
                          ),
                        ),
                      ],
                    ),
                    const RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution('OpenStreetMap'),
                      ],
                    ),
                  ],
                ),
              ),
              if (location.label.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    color: Colors.black.withValues(alpha: 0.5),
                    child: Text(
                      location.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.chatCaption.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
