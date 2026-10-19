import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';

import '../config/strings.dart';
import '../config/theme.dart';
import '../core/chat/chat_location.dart';
import '../core/media/chat_photo_helper.dart';
import '../providers/riverpod/locale_provider.dart';
import '../core/map_tile_provider.dart';
import 'media_caption_time.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bubble pesan LOKASI (ala WhatsApp): peta mini + label, tap → Google Maps.
///
/// Peta hanya-pandang (tanpa interaksi) supaya tidak merebut gesture scroll
/// chat. Bila tile gagal dimuat (offline), latar abu + ikon tetap tampil —
/// tombol buka Google Maps tetap bisa ditekan.
///
/// PETA TAMPIL AWAL (2026-10-14): `FlutterMap` langsung di-mount saat bubble
/// dibangun (bukan placeholder abu menunggu tap — keluhan user "harus diklik
/// dulu baru tampil"). Tile OSM diunduh asinkron per bubble yang terlihat
/// (ListView hanya membangun bubble di viewport + cacheExtent) + terisolasi
/// `RepaintBoundary`, jadi cold start tetap ringan; tap langsung buka Maps.
class LocationBubble extends ConsumerStatefulWidget {
  final ChatLocation location;

  /// Lebar kartu (null = lebar media chat 72% layar, sama foto/video).
  /// Pakai `double.infinity` di preview composer.
  final double? width;

  /// Tinggi peta (null = 0.6× lebar, rasio pratinjau maps WhatsApp).
  final double? height;

  /// Preview composer = true (bisa digeser + peta langsung tampil). Bubble
  /// chat = false (placeholder statis; tap = buka peta/Maps).
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
    this.width,
    this.height,
    this.interactive = false,
    this.onTapOverride,
    this.timeStr = '',
    this.showChecks = false,
    this.isPending = false,
    this.isQueued = false,
    this.isRead = false,
  });

  @override
  ConsumerState<LocationBubble> createState() => _LocationBubbleState();
}

class _LocationBubbleState extends ConsumerState<LocationBubble> {
  /// Badge lokasi live menampilkan "berakhir N menit" — tanpa ticker nilainya
  /// membeku sampai ada hal lain yang memicu rebuild. Timer 1 menit cukup
  /// (resolusi teks = menit) dan hanya hidup untuk pesan LIVE.
  Timer? _liveTick;

  ChatLocation get location => widget.location;
  bool get interactive => widget.interactive;
  double get width =>
      widget.width ?? chatMediaWidth(MediaQuery.sizeOf(context).width);
  double get height => widget.height ?? width * 0.6;
  String get timeStr => widget.timeStr;
  bool get showChecks => widget.showChecks;
  bool get isPending => widget.isPending;
  bool get isQueued => widget.isQueued;
  bool get isRead => widget.isRead;

  @override
  void initState() {
    super.initState();
    _syncLiveTick();
  }

  @override
  void didUpdateWidget(covariant LocationBubble old) {
    super.didUpdateWidget(old);
    // Pesan yang sama bisa berubah status live-nya (update koordinat dari
    // pengirim) — pastikan ticker ikut menyesuaikan.
    if (old.location.live != widget.location.live) _syncLiveTick();
  }

  /// Nyalakan ticker HANYA untuk lokasi live yang belum kedaluwarsa.
  /// Timer berhenti sendiri saat waktu habis (tidak ada rebuild sia-sia).
  void _syncLiveTick() {
    _liveTick?.cancel();
    _liveTick = null;
    final loc = widget.location;
    if (!loc.live) return;
    final exp = loc.expiresAt;
    if (exp == null || !exp.isAfter(DateTime.now().toUtc())) return;
    _liveTick = Timer.periodic(const Duration(minutes: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final e = widget.location.expiresAt;
      if (e == null || !e.isAfter(DateTime.now().toUtc())) {
        t.cancel();
        _liveTick = null;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _liveTick?.cancel();
    super.dispose();
  }

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
    final s = ref.watch(localeProvider).s;
    return GestureDetector(
      // opaque: seluruh area bubble menerima tap walau child (peta) tidak
      // hit-testable di beberapa kondisi → tap pasti sampai ke handler.
      behavior: HitTestBehavior.opaque,
      onTap: () {
        final cb = widget.onTapOverride;
        if (cb != null) {
          cb();
          return;
        }
        // Peta tampil sejak awal → tap langsung buka Google Maps.
        _open(context);
      },
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Clip HANYA peta (sudut membulat) — caption/jam di bawah TIDAK
            // ikut terpotong radius bawah.
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
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
                        // RepaintBoundary: isolasi repaint peta dari sisa bubble
                        // & list → scroll/mount bubble lain tidak memicu raster
                        // ulang tile peta (terukur: buka chat banyak lokasi =
                        // frame raster berat ~58ms tanpa isolasi).
                        child: RepaintBoundary(
                          // Latar abu di BAWAH peta: saat tile masih diunduh /
                          // offline, kartu tetap terlihat berisi (bukan hitam).
                          child: Container(
                            color: AppTheme.bgInput,
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
                                urlTemplate: osmTileUrl,
                                userAgentPackageName: 'com.chatyuk.chatyuk',
                                // Provider BERSAMA + cache disk: scroll ulang
                                // histori chat tidak mengunduh tile lagi.
                                tileProvider: basicMapTiles,
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
                        ), // FlutterMap
                      ), // Container abu (latar saat tile loading/offline)
                    ), // RepaintBoundary
                  ), // IgnorePointer
                ), // Positioned.fill
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
              // Caption + jam ala chat teks; jam rata kanan sejajar tepi peta.
              // Tanpa caption → jam di bawah peta, rata kanan.
              if (location.caption.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
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
                  padding: const EdgeInsets.fromLTRB(8, 2, 0, 2),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: _timeRow(),
                  ),
                ),
            ],
          ),
        ),
    );
  }
}
