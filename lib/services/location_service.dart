import 'dart:async';
import 'dart:convert';
import '../utils.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/cache/message_cache.dart';
import 'geo_service.dart';

/// Satu tempat terdekat (hasil reverse-geocode alamat atau POI Overpass).
class NearbyPlace {
  final String name;
  final double lat;
  final double lng;
  final String address;
  const NearbyPlace({
    required this.name,
    required this.lat,
    required this.lng,
    this.address = '',
  });
}

/// Hasil fix lokasi device + metadata anti-spoof.
/// `mocked` = Android menandai lokasi dari mock provider (Fake GPS);
/// `accuracy` = akurasi meter (0/negatif = khas mock). Keduanya
/// diteruskan ke server (heuristik tambahan di `update_my_location`).
class DeviceFix {
  final double lat;
  final double lon;
  final bool mocked;
  final int? accuracy;
  const DeviceFix(this.lat, this.lon, {this.mocked = false, this.accuracy});
}

/// Asal sebuah fix lokasi — menentukan seberapa "segar" koordinatnya.
/// `cache` = snapshot persist sesi lalu, `lastKnown` = cache OS,
/// `gps` = fix baru dari sensor.
enum FixSource { cache, lastKnown, gps }

/// Koordinat + akurasi + asal. Dipakai jalur cepat pemilih lokasi:
/// sheet langsung tampil memakai fix termurah, GPS menyusul.
class LocationFix {
  final double lat;
  final double lng;
  final int accuracyM;
  final FixSource source;

  /// Waktu fix diambil. `null` = baru saja (default pemanggil stream).
  final DateTime? at;
  const LocationFix(
    this.lat,
    this.lng, {
    this.accuracyM = 0,
    this.source = FixSource.gps,
    this.at,
  });

  /// Sudah pasti didapat dari GPS (bukan cache/last-known) — aman dikirim
  /// langsung tanpa menunggu refine.
  bool get isPrecise => source == FixSource.gps;

  /// Umur fix; besar bila tidak diketahui.
  Duration get age {
    final t = at;
    return t == null ? Duration.zero : DateTime.now().difference(t);
  }
}

/// Hasil bertahap data sekitar: [address] dulu (cepat, lokal/OS),
/// [places] menyusul dari Overpass (jaringan lambat).
class NearbyData {
  /// Alamat titik pusat ('' = belum/gagal).
  final String address;

  /// Titik pusat + POI sekitar. Kosong pada emisi pertama.
  final List<NearbyPlace> places;

  /// true = POI sudah final (berhasil ATAU gagal) — spinner harus berhenti.
  final bool placesDone;
  const NearbyData({
    this.address = '',
    this.places = const [],
    this.placesDone = false,
  });
}

/// Ambil & simpan lokasi user dengan strategi dua sumber (Opsi B):
/// - Kalau izin lokasi SUDAH diberikan → koordinat presisi dari device
///   (GPS/Wi-Fi/tower). Tidak pernah MEMICU dialog izin di sini —
///   hanya dipakai kalau user sudah menyetujui sebelumnya.
/// - Kalau belum/ditolak → perkiraan koordinat via IP geolocation.
/// Hasil disimpan ke profiles lewat RPC update_my_location.
class LocationService {
  final SupabaseClient _sb;
  LocationService([SupabaseClient? sb]) : _sb = sb ?? Supabase.instance.client;

  // ── Cache status izin & service ──
  // Sebelumnya satu tap "kirim lokasi" memanggil isLocationServiceEnabled()
  // + checkPermission() 4x terpisah (±8 hop platform channel). Sekarang
  // di-cache singkat: status izin tak berubah dalam hitungan detik, dan
  // dialog izin hanya bisa muncul lewat requestPermission() yang selalu
  // me-refresh cache.
  static const _permTtl = Duration(seconds: 5);
  DateTime? _permAt;
  LocationPermission? _permCache;
  bool? _svcCache;

  /// Apakah service lokasi menyala + izin sudah diberikan. Satu hop saja.
  Future<bool> hasPermission() async {
    final perm = await _permissionCached();
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  Future<LocationPermission> _permissionCached() async {
    final at = _permAt;
    final cached = _permCache;
    if (at != null &&
        cached != null &&
        DateTime.now().difference(at) < _permTtl) {
      return cached;
    }
    var perm = LocationPermission.denied;
    try {
      _svcCache = await Geolocator.isLocationServiceEnabled();
      if (_svcCache == true) perm = await Geolocator.checkPermission();
    } catch (e) {
      dlog('[location] permission cache error: $e');
    }
    _permCache = perm;
    _permAt = DateTime.now();
    return perm;
  }

  /// Buang cache izin (dipanggil setelah dialog izin / buka Settings).
  void invalidatePermissionCache() {
    _permAt = null;
    _permCache = null;
    _svcCache = null;
  }

  /// Perbarui lokasi user aktif. Return sumber yang dipakai: 'gps' | 'ip' | null.
  Future<String?> updateMyLocation() async {
    // 1. Coba lokasi device jika izin SUDAH ada (tanpa memicu dialog).
    final gps = await _tryDevicePosition();
    if (gps != null) {
      await _save(gps.lat, gps.lon, 'gps', null, gps.mocked, gps.accuracy);
      return 'gps';
    }
    // 2. Fallback: perkiraan via IP.
    try {
      final info = await GeoService().detect();
      if (info?.lat != null && info?.lon != null) {
        await _save(info!.lat!, info.lon!, 'ip', info.ipAddress);
        return 'ip';
      }
    } catch (e) {
      dlog('[location] ip fallback error: $e');
    }
    return null;
  }

  /// Ambil koordinat device HANYA jika izin sudah diberikan sebelumnya.
  /// Tidak memanggil requestPermission → tidak ada dialog paksaan.
  /// Prioritas: fix GPS fresh (akurasi tinggi); last-known hanya dipakai
  /// kalau masih segar (≤ 10 menit) — cache lama sering salah lokasi.
  Future<DeviceFix?> _tryDevicePosition() async {
    try {
      if (!await hasPermission()) {
        return null; // belum diizinkan → jangan minta, biar IP yang handle
      }
      // Fallback chain akurasi: high (GPS satelit) → medium → low
      // (network/cell). Di dalam ruangan GPS satelit sering tidak fix
      // dalam 10 detik — network provider tetap akurat puluhan meter.
      // (2026-10-14) Timeout diturunkan 20s→10s per tahap: 3 tahap × 20s
      // = 60s tanpa umpan balik adalah penyebab utama sheet lokasi "delay".
      for (final acc in const [
        LocationAccuracy.high,
        LocationAccuracy.medium,
        LocationAccuracy.low,
      ]) {
        try {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: LocationSettings(
              accuracy: acc,
              timeLimit: const Duration(seconds: 10),
            ),
          );
          return DeviceFix(
            pos.latitude,
            pos.longitude,
            // isMocked = Android menandai provider lokasi palsu (Fake GPS).
            // Bisa dilewati sebagian app → server juga pakai heuristik.
            mocked: pos.isMocked,
            accuracy: pos.accuracy.isFinite ? pos.accuracy.round() : null,
          );
        } catch (e) {
          dlog('[location] getCurrentPosition $acc error: $e');
        }
      }
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null &&
            DateTime.now().difference(last.timestamp).inMinutes <= 10) {
          return DeviceFix(
            last.latitude,
            last.longitude,
            mocked: last.isMocked,
            accuracy: last.accuracy.isFinite ? last.accuracy.round() : null,
          );
        }
      } catch (e) {
        dlog('[location] last known error: $e');
      }
      return null;
    } catch (e) {
      dlog('[location] device position error: $e');
      return null;
    }
  }

  /// Variasi publik untuk register: ambil posisi device (tanpa dialog izin).
  Future<DeviceFix?> tryDevicePositionForRegister() => _tryDevicePosition();

  /// Ambil last-known position CEPAT (tanpa chain GPS yang bisa blokir
  /// puluhan detik). Return (lat, lon) bila izin ada & posisi masih segar
  /// (≤ 10 menit). Dipakai layar "Orang Sekitar" supaya radar langsung
  /// tampil memakai posisi terakhir, sementara GPS akurat jalan di
  /// belakang.
  Future<(double, double)?> lastKnownPosition() async {
    try {
      if (!await hasPermission()) return null;
      final last = await Geolocator.getLastKnownPosition();
      if (last != null &&
          DateTime.now().difference(last.timestamp).inMinutes <= 10) {
        return (last.latitude, last.longitude);
      }
      return null;
    } catch (e) {
      dlog('[location] lastKnownPosition error: $e');
      return null;
    }
  }

  /// Minta izin lokasi secara eksplisit (dipanggil dari tombol "aktifkan
  /// lokasi presisi", BUKAN otomatis). Return true jika diberikan.
  Future<bool> requestPermission() async {
    try {
      // Paksa baca ulang: dialog izin baru saja mungkin mengubah status.
      invalidatePermissionCache();
      if (!await Geolocator.isLocationServiceEnabled()) {
        _svcCache = false;
        return false;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      // Simpan hasil dialog supaya pemanggil berikutnya gratis.
      _permCache = perm;
      _permAt = DateTime.now();
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (e) {
      dlog('[location] requestPermission error: $e');
      return false;
    }
  }

  /// Buka halaman izin app di Pengaturan sistem (untuk user yang pernah
  /// memilih "kira-kira" sehingga Android tidak menampilkan dialog lagi).
  Future<void> openSettings() async {
    try {
      invalidatePermissionCache();
      await Geolocator.openAppSettings();
    } catch (e) {
      dlog('[location] openSettings error: $e');
    }
  }

  Future<void> _save(
    double lat,
    double lon,
    String source, [
    String? ip,
    bool mocked = false,
    int? accuracy,
  ]) async {
    try {
      await _sb.rpc(
        'update_my_location',
        params: {
          'p_lat': lat,
          'p_lon': lon,
          'p_source': source,
          // Selalu kirim argumen penuh — server punya overload RPC lain;
          // PostgREST error "ambiguous" kalau argumen tak lengkap.
          'p_ip': ip ?? '',
          'p_mocked': mocked,
          'p_accuracy': accuracy,
        },
      );
    } catch (e) {
      dlog('[location] save error: $e');
    }
  }

  /// Aktif/nonaktifkan berbagi lokasi untuk fitur "orang sekitar".
  Future<void> setShareLocation(bool value) async {
    final id = _sb.auth.currentUser?.id;
    if (id == null) return;
    try {
      await _sb.from('profiles').update({'share_location': value}).eq('id', id);
    } catch (e) {
      dlog('[location] setShareLocation error: $e');
    }
  }

  /// Ambil daftar orang sekitar dalam radius (km). Return list map:
  /// uid, nickname, gender, age, country, city, status, avatar,
  /// is_registered, last_seen, distance_km.
  Future<List<Map<String, dynamic>>> nearbyUsers(
    double radiusKm, {
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _sb.rpc(
      'nearby_users',
      params: {
        'p_radius_km': radiusKm,
        'p_limit': limit,
        if (offset > 0) 'p_offset': offset,
      },
    );
    final list = res is List ? res : <dynamic>[];
    return list.cast<Map<String, dynamic>>();
  }

  /// Posisi presisi terbaru (untuk berbagi lokasi & lokasi live).
  /// Return (lat, lng, accuracyM) atau null bila gagal/tanpa izin.
  ///
  /// (2026-10-14) Timeout 20s→8s lalu fallback network: satu-satunya
  /// pemakai di jalur user-facing yang butuh presisi tinggi adalah
  /// `positionStream()` (sudah punya last-known lebih dulu) dan ticker
  /// lokasi live. 8 detik cukup untuk fix satelit di luar ruangan; di
  /// dalam ruangan network fix puluhan meter tetap lebih baik daripada
  /// menunggu 12 detik tambahan tanpa hasil.
  Future<(double, double, int)?> precisePosition({
    Duration timeLimit = const Duration(seconds: 8),
    bool fallbackToNetwork = true,
  }) async {
    try {
      if (!await hasPermission()) return null;
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: timeLimit,
          ),
        );
        return (pos.latitude, pos.longitude, _acc(pos.accuracy));
      } catch (e) {
        dlog('[location] precisePosition high error: $e');
      }
      if (!fallbackToNetwork) return null;
      // Tahap 2: network/cell provider — cepat, akurasi puluhan meter.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: timeLimit,
        ),
      );
      return (pos.latitude, pos.longitude, _acc(pos.accuracy));
    } catch (e) {
      dlog('[location] precisePosition error: $e');
      return null;
    }
  }

  int _acc(double v) => v.isFinite && v > 0 ? v.round() : 0;

  // ── Fix terakhir (persist) ──
  static const _lastFixKey = 'loc:last';

  /// Fix koordinat terakhir lintas sesi — SINKRON, tanpa await.
  /// Dipakai pemilih lokasi supaya peta langsung punya titik pusat.
  LocationFix? cachedFix({Duration maxAge = const Duration(hours: 12)}) {
    try {
      final obj = MessageCache.instance.peekRawObj(_lastFixKey);
      if (obj.isEmpty) return null;
      final lat = (obj['lat'] as num?)?.toDouble();
      final lng = (obj['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
      final at = DateTime.tryParse((obj['at'] as String?) ?? '');
      if (at == null || DateTime.now().difference(at) > maxAge) return null;
      return LocationFix(
        lat,
        lng,
        accuracyM: (obj['acc'] as num?)?.toInt() ?? 0,
        source: FixSource.cache,
        at: at,
      );
    } catch (_) {
      return null;
    }
  }

  /// Simpan fix (memori langsung, disk di belakang) untuk buka sheet berikutnya.
  void _rememberFix(double lat, double lng, int acc) {
    try {
      MessageCache.instance.saveRawObj(_lastFixKey, {
        'lat': lat,
        'lng': lng,
        'acc': acc,
        'at': DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  /// Stream posisi berjenjang: cache → last-known OS → GPS presisi.
  ///
  /// Pemakai (sheet kirim lokasi) menampilkan UI pada frame pertama dan
  /// membiarkan stream ini mengisi/menggeser peta sesudahnya. Emisi bisa
  /// datang 2-3 kali dengan akurasi makin baik; tidak pernah error.
  Stream<LocationFix> positionStream() {
    late StreamController<LocationFix> ctrl;
    var closed = false;
    void emit(LocationFix f) {
      if (!closed) ctrl.add(f);
    }

    Future<void> run() async {
      try {
        final cached = cachedFix();
        if (cached != null) emit(cached);
        if (!await hasPermission()) return;
        try {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) {
            final acc = _acc(last.accuracy);
            // Posisi OS yang sangat basi tetap berguna sebagai titik pusat,
            // asal jangan dipakai untuk kirim (ditandai lastKnown).
            emit(LocationFix(
              last.latitude,
              last.longitude,
              accuracyM: acc,
              source: FixSource.lastKnown,
              at: last.timestamp,
            ));
          }
        } catch (e) {
          dlog('[location] stream lastKnown error: $e');
        }
        // Fix baru: high → fallback medium (total ±16s, di luar jalur UI).
        final precise = await precisePosition();
        if (precise != null) {
          _rememberFix(precise.$1, precise.$2, precise.$3);
          emit(LocationFix(
            precise.$1,
            precise.$2,
            accuracyM: precise.$3,
            source: FixSource.gps,
          ));
        }
      } catch (e) {
        // Apa pun yang lolos: JANGAN biarkan stream menggantung tanpa close
        // (pemakai menunggu onDone untuk berhenti menampilkan status).
        dlog('[location] stream error: $e');
      } finally {
        if (!closed) await ctrl.close();
      }
    }

    ctrl = StreamController<LocationFix>(
      onListen: () => unawaited(run()),
      onCancel: () {
        closed = true;
      },
    );
    return ctrl.stream;
  }

  // ── Reverse geocode (LRU memori) ──
  // Alamat tidak berubah dalam hitungan menit; sheet yang dibuka-tutup
  // berulang di titik yang sama tidak perlu memanggil Geocoder native
  // (di iOS: panggilan jaringan) berkali-kali.
  static const _addrTtl = Duration(minutes: 10);
  static const _addrMax = 32;
  final Map<String, (String, DateTime)> _addrCache = {};
  final Map<String, (List<NearbyPlace>, DateTime)> _poiCache = {};

  String _addrKey(double lat, double lng) =>
      '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

  /// Alamat/label dari koordinat (reverse geocode) — ala WhatsApp
  /// "Jl. Mukodar Tengah, Cimahi, 40535". '' bila gagal.
  Future<String> addressLabel(double lat, double lng) async {
    final key = _addrKey(lat, lng);
    final hit = _addrCache[key];
    if (hit != null && DateTime.now().difference(hit.$2) < _addrTtl) {
      return hit.$1;
    }
    try {
      final places = await placemarkFromCoordinates(lat, lng);
      if (places.isEmpty) return '';
      final p = places.first;
      final parts = <String>[
        if ((p.street ?? '').isNotEmpty) p.street!,
        if ((p.subLocality ?? '').isNotEmpty) p.subLocality!,
        if ((p.locality ?? '').isNotEmpty) p.locality!,
        if ((p.postalCode ?? '').isNotEmpty) p.postalCode!,
      ];
      final label = parts.isNotEmpty ? parts.join(', ') : (p.name ?? '');
      if (label.isNotEmpty) {
        if (_addrCache.length >= _addrMax) {
          _addrCache.remove(_addrCache.keys.first);
        }
        _addrCache[key] = (label, DateTime.now());
      }
      return label;
    } catch (e) {
      dlog('[location] addressLabel error: $e');
      return '';
    }
  }

  /// Tempat terdekat (POI) via Overpass API (OpenStreetMap) — gratis,
  /// tanpa API key. Menampilkan alamat titik + beberapa tempat sekitar
  /// (masjid, kafe, sekolah, dll) dalam radius [radiusM].
  Future<List<NearbyPlace>> nearbyPlaces(
    double lat,
    double lng, {
    int radiusM = 400,
    int limit = 8,
  }) async {
    final addr = await addressLabel(lat, lng);
    final out = <NearbyPlace>[
      NearbyPlace(
        name: addr.isNotEmpty ? addr : '$lat, $lng',
        lat: lat,
        lng: lng,
        address: addr,
      ),
    ];
    out.addAll(await _overpassPois(lat, lng, radiusM: radiusM, limit: limit));
    return out;
  }

  /// Versi BERTAHAP untuk sheet pemilih lokasi: alamat diemisi duluan
  /// (cepat), POI menyusul. Sebelumnya keduanya serial di dalam satu
  /// Future → label alamat ikut tertahan timeout Overpass 20 detik.
  Stream<NearbyData> nearbyData(
    double lat,
    double lng, {
    int radiusM = 400,
    int limit = 8,
  }) async* {
    // Jalan bersamaan: alamat & POI tidak saling bergantung.
    final addrFuture = addressLabel(lat, lng);
    final poiFuture = _overpassPois(lat, lng, radiusM: radiusM, limit: limit);

    final addr = await addrFuture;
    yield NearbyData(address: addr);

    final pois = await poiFuture;
    final out = <NearbyPlace>[
      NearbyPlace(
        name: addr.isNotEmpty ? addr : '$lat, $lng',
        lat: lat,
        lng: lng,
        address: addr,
      ),
      ...pois,
    ];
    yield NearbyData(address: addr, places: out, placesDone: true);
  }

  /// POI Overpass (dengan cache per grid ±200 m). Timeout 8s + satu
  /// mirror. Gagal = list kosong (sheet tetap bisa kirim lokasi).
  Future<List<NearbyPlace>> _overpassPois(
    double lat,
    double lng, {
    int radiusM = 400,
    int limit = 8,
  }) async {
    final key = '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
    final hit = _poiCache[key];
    if (hit != null && DateTime.now().difference(hit.$2) < _addrTtl) {
      return hit.$1;
    }
    final query =
        '[out:json][timeout:10];'
        '(node(around:$radiusM,$lat,$lng)["name"]["amenity"];'
        'node(around:$radiusM,$lat,$lng)["name"]["shop"];'
        'node(around:$radiusM,$lat,$lng)["name"]["tourism"];'
        ');'
        'out center $limit;';
    const mirrors = <String>[
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
    ];
    for (final url in mirrors) {
      try {
        final res = await http
            .post(Uri.parse(url), body: {'data': query})
            .timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) continue;
        final data = jsonDecode(res.body);
        final elems = (data['elements'] as List?) ?? const [];
        final out = <NearbyPlace>[];
        for (final e in elems) {
          final name = (e['tags']?['name']) as String?;
          if (name == null || name.isEmpty) continue;
          final elat = (e['lat'] as num?)?.toDouble();
          final elng = (e['lon'] as num?)?.toDouble();
          if (elat == null || elng == null) continue;
          out.add(NearbyPlace(name: name, lat: elat, lng: elng));
          if (out.length >= limit) break;
        }
        if (_poiCache.length >= _addrMax) {
          _poiCache.remove(_poiCache.keys.first);
        }
        _poiCache[key] = (out, DateTime.now());
        return out;
      } catch (e) {
        dlog('[location] overpass ($url) error: $e');
      }
    }
    // Gagal total: cache hasil kosong singkat supaya tidak hammer server
    // saat user buka-tutup sheet berulang kali.
    _poiCache[key] = (const <NearbyPlace>[], DateTime.now());
    return const <NearbyPlace>[];
  }
}
