import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../config/theme.dart';
import '../config/strings.dart';
import '../core/chat/chat_location.dart';
import '../providers/riverpod/locale_provider.dart';
import '../providers/riverpod/location_provider.dart';
import '../core/map_tile_provider.dart';
import 'skeleton_card.dart';

/// Alur "kirim lokasi" ala WhatsApp: sheet tampil DULU, posisi menyusul.
///
/// (2026-10-14) Sebelumnya fungsi ini meng-`await` izin → GPS high (20s) →
/// last-known → chain 3×20s SEBELUM `showModalBottomSheet`. Di dalam
/// ruangan, GPS sering gagal fix → user menatap layar beku 20–80 detik
/// tanpa spinner. Sekarang:
///   1. cek izin murah (±1 hop, ter-cache),
///   2. sheet langsung slide (frame pertama),
///   3. `_LocationPickerSheet` berlangganan stream posisi dan menggeser
///      peta + mengaktifkan tombol kirim begitu fix masuk.
///
/// Return [ChatLocation] begitu user memilih salah satu opsi; null bila batal
/// ATAU izin ditolak (pesan error via [messenger]).
///
/// Dipakai bersama private & room supaya perilakunya identik.
Future<ChatLocation?> pickChatLocation(
  BuildContext context, {
  required ScaffoldMessengerState messenger,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final s = container.read(localeProvider).s;
  final loc = container.read(locationProvider);

  // 1. Izin — satu hop ter-cache. Dialog sistem hanya bila memang belum
  //    pernah ditanya (kondisi dingin, sekali seumur instalasi), dan itu
  //    harus terjadi SEBELUM sheet supaya tidak muncul di atasnya.
  if (!await loc.hasPermission()) {
    final granted = await loc.requestPermission();
    if (!granted) {
      messenger.showSnackBar(SnackBar(content: Text(s.locPermissionDenied)));
      return null;
    }
  }
  if (!context.mounted) return null;

  // 2. Sheet langsung tampil — titik pusat awal dari cache (sinkron), GPS
  //    menyusul di dalam sheet.
  return showLocationPickerSheet(context);
}

/// Sheet pemilih lokasi (ala WhatsApp): peta + daftar opsi.
///
/// [initial] opsional: titik pusat awal. Bila null, diambil dari fix
/// terakhir yang tersimpan (`LocationNotifier.cachedFix()`).
Future<ChatLocation?> showLocationPickerSheet(
  BuildContext context, {
  LocationFix? initial,
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
    builder: (_) => _LocationPickerSheet(initial: initial, accuracyM: accuracyM),
  );
}

class _LocationPickerSheet extends ConsumerStatefulWidget {
  final LocationFix? initial;
  final int accuracyM;
  const _LocationPickerSheet({this.initial, this.accuracyM = 0});

  @override
  ConsumerState<_LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends ConsumerState<_LocationPickerSheet> {
  /// Titik aktif. Null = belum ada koordinat sama sekali (peta world-view,
  /// tombol kirim dinonaktifkan) — kondisi langka: tanpa izin & tanpa cache.
  LocationFix? _fix;

  /// User sudah menggeser/ketuk peta → jangan override dengan fix GPS.
  bool _userMoved = false;

  /// GPS masih mencari fix baru (setelah cache/last-known tampil).
  bool _refining = true;

  String _address = '';
  List<NearbyPlace> _places = const [];
  bool _placesLoading = true;
  bool _placesEmpty = false;

  final MapController _mapCtrl = MapController();
  StreamSubscription<LocationFix>? _posSub;
  StreamSubscription<NearbyData>? _nearbySub;
  Timer? _tapDebounce;
  bool _mapReady = false;

  /// Zoom awal: dekat bila sudah ada titik, jauh bila belum.
  static const _zoomNear = 16.0;
  static const _zoomFar = 4.0;
  static const _worldCenter = LatLng(-2.5, 118.0);

  // Pilihan durasi lokasi live (menit): 15 menit / 1 jam / 8 jam.
  static const _liveDurations = <int>[15, 60, 480];

  @override
  void initState() {
    super.initState();
    // 1 (SINKRON, 0 ms): pakai titik terakhir — peta langsung punya pusat.
    _fix = widget.initial ?? ref.read(locationProvider).cachedFix();
    _startPosition();
  }

  void _startPosition() {
    // 2 (ASYNC, di belakang): cache → last-known → GPS presisi.
    _posSub = ref.read(locationProvider).positionStream().listen((f) {
      if (!mounted) return;
      // Fix GPS selalu menang atas cache; last-known hanya dipakai bila
      // belum ada titik sama sekali. Setelah user geser peta: diam.
      final current = _fix;
      final better = current == null ||
          f.source.index > current.source.index ||
          (f.source == current.source && f.accuracyM > 0 &&
              (current.accuracyM <= 0 || f.accuracyM < current.accuracyM));
      final isFinal = f.source == FixSource.gps;
      setState(() {
        if (!_userMoved && better) {
          _fix = f;
          _centerOn(f);
        }
        _refining = !isFinal && !_userMoved;
      });
      if (better && !_userMoved) _loadNearby(f.lat, f.lng);
      if (isFinal) {
        _posSub?.cancel();
        _posSub = null;
      }
    }, onDone: () {
      if (mounted) setState(() => _refining = false);
    });
    if (_fix != null) _loadNearby(_fix!.lat, _fix!.lng);
  }

  void _centerOn(LocationFix f) {
    if (!_mapReady) return;
    try {
      _mapCtrl.move(LatLng(f.lat, f.lng), _zoomNear);
    } catch (_) {
      // Peta belum siap (race saat frame pertama) — abaikan, bukan error.
    }
  }

  /// Muat alamat + POI bertahap untuk titik [lat],[lng].
  /// Dedupe: pemanggilan berulang untuk titik yang SAMA (mis. cache dari
  /// `initState` lalu emisi pertama `positionStream` yang juga cache) tidak
  /// menembak Geocoder/Overpass dua kali.
  String? _nearbyKey;

  /// Penanda pemanggilan pertama (dari `initState`) — lihat `_loadNearby`.
  bool _firstNearbyLoad = true;
  void _loadNearby(double lat, double lng) {
    final key = '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';
    if (key == _nearbyKey) return;
    _nearbyKey = key;
    _nearbySub?.cancel();
    // `setState` saat initState (sebelum build pertama) ditolak assert pada
    // beberapa versi Flutter — penugasan langsung lebih aman & setara.
    if (_firstNearbyLoad) {
      _placesLoading = true;
      _placesEmpty = false;
    } else {
      setState(() {
        _placesLoading = true;
        _placesEmpty = false;
      });
    }
    _firstNearbyLoad = false;
    _nearbySub = ref.read(locationProvider).nearbyData(lat, lng).listen((d) {
      if (!mounted) return;
      setState(() {
        _address = d.address.isNotEmpty ? d.address : _address;
        if (d.placesDone) {
          _places = d.places;
          _placesLoading = false;
          _placesEmpty = d.places.length <= 1;
        }
      });
    }, onError: (Object e) {
      if (!mounted) return;
      setState(() => _placesLoading = false);
    }, onDone: () {
      if (mounted && _placesLoading) {
        setState(() => _placesLoading = false);
      }
    });
  }

  /// Ketuk peta = pindahkan penanda. Alamat & POI dimuat ulang (debounce
  /// 400 ms) supaya tidak membanjiri Geocoder/Overpass saat user mengetuk
  /// berkali-kali.
  void _onMapTap(TapPosition _, LatLng point) {
    setState(() {
      _userMoved = true;
      _refining = false;
      _fix = LocationFix(point.latitude, point.longitude, source: FixSource.gps);
    });
    _tapDebounce?.cancel();
    _tapDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      _loadNearby(point.latitude, point.longitude);
    });
  }

  void _resetToMe() {
    final last = ref.read(locationProvider).cachedFix();
    _posSub?.cancel();
    _posSub = null;
    setState(() {
      _userMoved = false;
      _refining = true;
      if (last != null) _fix = last;
    });
    if (last != null) _centerOn(last);
    // `_startPosition` mengurus pemuatan alamat/POI untuk `_fix` saat ini
    // (dan dedupe mencegah request ganda bila titiknya sama).
    _startPosition();
  }

  void _send({
    String place = '',
    bool live = false,
    int minutes = 0,
    double? lat,
    double? lng,
    String? label,
  }) {
    final f = _fix;
    final sendLat = lat ?? f?.lat;
    final sendLng = lng ?? f?.lng;
    // Tidak ada koordinat sama sekali = tidak ada yang bisa dikirim.
    if (sendLat == null || sendLng == null) return;
    final exp =
        live ? DateTime.now().toUtc().add(Duration(minutes: minutes)) : null;
    Navigator.pop(
      context,
      ChatLocation(
        lat: sendLat,
        lng: sendLng,
        label: label ?? _address,
        place: place,
        live: live,
        expiresAt: exp,
        accuracyM: widget.accuracyM > 0 ? widget.accuracyM : (f?.accuracyM ?? 0),
      ),
    );
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _nearbySub?.cancel();
    _tapDebounce?.cancel();
    _mapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(localeProvider).s;
    final navPad = MediaQuery.of(context).padding.bottom;
    final bottomPad = navPad > 64 ? navPad : 64.0;
    final fix = _fix;
    final canSend = fix != null;
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
          // Peta mini (ketuk untuk pindah titik).
          SizedBox(
            height: 180,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: FlutterMap(
                        mapController: _mapCtrl,
                        options: MapOptions(
                          initialCenter: fix == null
                              ? _worldCenter
                              : LatLng(fix.lat, fix.lng),
                          initialZoom: fix == null ? _zoomFar : _zoomNear,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                          ),
                          onMapReady: () {
                            _mapReady = true;
                            // Fix bisa datang sebelum peta siap — susulkan.
                            final f = _fix;
                            if (f != null && !_userMoved) _centerOn(f);
                          },
                          onTap: _onMapTap,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: osmTileUrl,
                            userAgentPackageName: 'com.chatyuk.chatyuk',
                            tileProvider: basicMapTiles,
                            // Offline/gagal → latar netral, jangan kotak merah.
                            errorTileCallback: (_, _, _) {},
                          ),
                          MarkerLayer(
                            markers: [
                              if (fix != null)
                                Marker(
                                  point: LatLng(fix.lat, fix.lng),
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
                    // Overlay status: "Mendeteksi lokasi..." / akurasi.
                    Positioned(
                      left: 6,
                      top: 6,
                      child: _statusChip(s, fix),
                    ),
                    // Kembali ke posisi saya (setelah geser peta).
                    if (_userMoved)
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _resetToMe,
                            child: const Padding(
                              padding: EdgeInsets.all(7),
                              child: Icon(
                                Icons.my_location_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              _refining && canSend
                  ? s.locRefining
                  : (canSend ? s.locTapToPick : s.locFetching),
              style: AppText.caption.copyWith(
                color: _refining && canSend
                    ? AppTheme.textSecondary
                    : Colors.green,
              ),
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
                    color: canSend ? Colors.blue : AppTheme.textSecondary,
                    title: s.locSendCurrent,
                    subtitle: _address.isNotEmpty
                        ? _address
                        : (canSend ? null : s.locFetching),
                    onTap: canSend ? () => _send() : null,
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
                            onPressed:
                                canSend ? () => _send(live: true, minutes: m) : null,
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
                  if (!canSend)
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
                  else if (_placesLoading) ...[
                    // Skeleton (bukan spinner besar): POI Overpass memang
                    // jaringan pihak ketiga — biarkan bentuk list muncul
                    // duluan supaya tidak terasa "menggantung".
                    const SkeletonCard(height: 48),
                    const SkeletonCard(height: 48),
                    const SkeletonCard(height: 48),
                  ] else if (_placesEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Text(
                        s.locNoPlaces,
                        style: AppText.bodySmall.copyWith(
                          color: AppTheme.textSecondary,
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

  /// Chip status di pojok peta: sedang mencari / akurasi / perkiraan.
  Widget _statusChip(S s, LocationFix? fix) {
    final String label;
    Color dot;
    if (fix == null) {
      label = s.locFetching;
      dot = Colors.orangeAccent;
    } else if (_refining) {
      label = s.locRefining;
      dot = Colors.orangeAccent;
    } else if (fix.isPrecise && fix.accuracyM > 0) {
      label = s.locAccuracyTo(fix.accuracyM);
      dot = Colors.greenAccent;
    } else {
      label = s.locApproximate;
      dot = Colors.orangeAccent;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: AppText.micro.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  String _humanDuration(int minutes, S s) {
    if (minutes < 60) return s.locLiveMin(minutes);
    return s.locLiveHour(minutes ~/ 60);
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    required VoidCallback? onTap,
  }) {
    return ListTile(
      // Null = disabled: ListTile meredupkan sendiri, plus blokir tap.
      enabled: onTap != null,
      leading: Icon(icon, color: onTap != null ? color : null),
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
