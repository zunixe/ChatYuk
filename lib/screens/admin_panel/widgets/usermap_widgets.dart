import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../config/theme.dart';
import '../../../config/strings.dart';
import '../../../config/strings_admin.dart';
import '../../../providers/riverpod/locale_provider.dart';

class UserMapLegend extends StatelessWidget {
  const UserMapLegend({required this.s});
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
class UserMapFullscreenPage extends ConsumerStatefulWidget {
  const UserMapFullscreenPage({
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
  ConsumerState<UserMapFullscreenPage> createState() =>
      UserMapFullscreenState();
}

class UserMapFullscreenState extends ConsumerState<UserMapFullscreenPage> {
  final MapController _fsCtrl = MapController();
  // Batas marker sama dengan kartu — cegah beban render berlebih.
  static const _maxMarkers = 300;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
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
              child: UserMapBadge(
                text: widget.resolving
                    ? s.mapResolving
                    : '${widget.noLoc} ${s.mapNoLocation}',
              ),
            ),
          if (widget.withPos == 0 && !widget.resolving)
            Positioned(
              left: 12,
              top: 12,
              child: UserMapBadge(text: s.mapTapHint),
            ),
        ],
      ),
    );
  }
}

/// Badge kecil di atas peta (tanpa lokasi / hint). Dipakai mode layar penuh.
class UserMapBadge extends StatelessWidget {
  const UserMapBadge({required this.text});
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
