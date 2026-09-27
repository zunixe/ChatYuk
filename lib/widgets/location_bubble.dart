import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/chat/chat_location.dart';
import '../providers/locale_provider.dart';
import 'media_caption_time.dart';

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

  /// Preview composer = true (bisa digeser). Bubble chat = false (tap =
  /// buka Maps; peta di-IgnorePointer agar tap sampai ke pembungkus).
  final bool interactive;

  /// Override aksi tap — HANYA untuk test (null = buka Google Maps).
  final VoidCallback? onTapOverride;

  /// Jam kirim ("8:35 PM", "" = tidak tampil). Overlay kanan-bawah di atas
  /// peta — SAMA posisi dengan overlay jam foto/video (kanan 6 bawah 6).
  final String timeStr;

  /// Tampilkan centang dibaca (pengirim / monitor admin kedua sisi).
  final bool showChecks;
  final bool isPending;
  final bool isQueued;
  final bool isRead;
  const LocationBubble({
    super.key,
    required this.location,
    this.width = 220,
    this.height = 160,
    this.interactive = false,
    this.onTapOverride,
    this.timeStr = '',
    this.showChecks = false,
    this.isPending = false,
    this.isQueued = false,
    this.isRead = false,
  });

  /// Baris jam (+ centang) untuk kasus tanpa caption.
  Widget _timeRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          timeStr,
          style: AppText.chatTime.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
        if (showChecks) ...[
          const SizedBox(width: 3),
          Icon(
            (isPending || isQueued) ? Icons.done : Icons.done_all,
            size: 12,
            color: (!isQueued && !isPending && isRead)
                ? AppTheme.primary
                : AppTheme.textSecondary,
          ),
        ],
      ],
    );
  }

  /// Label badge lokasi live: sisa waktu ("berakhir 12 menit") atau
  /// "Lokasi live berakhir" bila kedaluwarsa.
  String _liveLabel(S s) {
    final exp = location.expiresAt;
    if (exp == null) return s.locLiveActive;
    final left = exp.difference(DateTime.now().toUtc());
    if (left.isNegative) return s.locLiveEnded;
    final mins = left.inMinutes;
    if (mins <= 0) return s.locLiveActive;
    return s.locLiveRemaining(mins);
  }

  Future<void> _open(BuildContext context) async {
    // Coba `geo:` dulu → langsung membuka app Maps (lebih andal & presisi
    // daripada link web yang bisa terblokir/redirect). Fallback ke URL web
    // bila tidak ada app yang menangani geo:.
    final geo = Uri.parse('geo:${location.lat},${location.lng}?q=${location.lat},${location.lng}');
    try {
      if (await canLaunchUrl(geo)) {
        await launchUrl(geo, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {}
    try {
      await launchUrl(
        Uri.parse(location.mapsUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<LocaleProvider>().s;
    return GestureDetector(
      // opaque: seluruh area bubble menerima tap walau child (peta) tidak
      // hit-testable di beberapa kondisi → tap pasti sampai ke handler.
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final cb = onTapOverride;
        if (cb != null) {
          cb();
          return;
        }
        _open(context);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: width,
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      // BUBBLE (non-interaktif): FlutterMap menyerap pointer
                      // walau InteractiveFlag.none → GestureDetector luar tak
                      // pernah dapat tap → Maps tidak terbuka. IgnorePointer
                      // melewatkan tap ke pembungkus. Preview composer
                      // (interactive) tetap bisa digeser.
                      child: IgnorePointer(
                        ignoring: !interactive,
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: LatLng(location.lat, location.lng),
                            initialZoom: 15,
                            interactionOptions: InteractionOptions(
                              flags: interactive
                                  ? InteractiveFlag.all &
                                      ~InteractiveFlag.rotate
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
                            // Badge lokasi LIVE (ala WhatsApp) di pojok kiri atas.
                            if (location.live)
                              Positioned(
                                left: 6,
                                top: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        location.isLiveActive
                                            ? Icons.gps_fixed_rounded
                                            : Icons.gps_off_rounded,
                                        size: 12,
                                        color: location.isLiveActive
                                            ? Colors.greenAccent
                                            : Colors.white70,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        _liveLabel(s),
                                        style: AppText.micro.copyWith(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // Atribusi OSM: diwajibkan, tapi cukup teks mungil
                            // di pojok KIRI bawah (bukan badge RichAttribution
                            // yang mencolok & menutupi peta). Kiri supaya
                            // tidak tertutup badge jam kanan-bawah di bubble
                            // chat (lihat private_chat_message.dart).
                            Positioned(
                              left: 2,
                              bottom: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                  vertical: 1,
                                ),
                                color: Colors.white.withValues(alpha: 0.55),
                                child: Text(
                                  '© OSM',
                                  style: AppText.micro.copyWith(
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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
              // Caption + jam ala chat teks; jam rata kanan sejajar tepi peta.
              // Tanpa caption → jam di bawah peta, rata kanan.
              if (location.caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: MediaCaptionTime(
                    text: location.caption,
                    timeStr: timeStr,
                    textStyle: AppText.chatBody.copyWith(
                      color: AppTheme.textPrimary,
                    ),
                    timeStyle: AppText.chatTime.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    showChecks: showChecks,
                    isPending: isPending,
                    isQueued: isQueued,
                    isRead: isRead,
                    leftInset: 8,
                  ),
                )
              else if (timeStr.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 0, 0),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _timeRow(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
