import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'geo_service.dart';

/// Ambil & simpan lokasi user dengan strategi dua sumber (Opsi B):
/// - Kalau izin lokasi SUDAH diberikan → koordinat presisi dari device
///   (GPS/Wi-Fi/tower). Tidak pernah MEMICU dialog izin di sini —
///   hanya dipakai kalau user sudah menyetujui sebelumnya.
/// - Kalau belum/ditolak → perkiraan koordinat via IP geolocation.
/// Hasil disimpan ke profiles lewat RPC update_my_location.
class LocationService {
  final SupabaseClient _sb;
  LocationService([SupabaseClient? sb]) : _sb = sb ?? Supabase.instance.client;

  /// Perbarui lokasi user aktif. Return sumber yang dipakai: 'gps' | 'ip' | null.
  Future<String?> updateMyLocation() async {
    // 1. Coba lokasi device jika izin SUDAH ada (tanpa memicu dialog).
    final gps = await _tryDevicePosition();
    if (gps != null) {
      await _save(gps.$1, gps.$2, 'gps');
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
      debugPrint('[location] ip fallback error: $e');
    }
    return null;
  }

  /// Ambil koordinat device HANYA jika izin sudah diberikan sebelumnya.
  /// Tidak memanggil requestPermission → tidak ada dialog paksaan.
  /// Prioritas: fix GPS fresh (akurasi tinggi); last-known hanya dipakai
  /// kalau masih segar (≤ 10 menit) — cache lama sering salah lokasi.
  Future<(double, double)?> _tryDevicePosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.always &&
          perm != LocationPermission.whileInUse) {
        return null; // belum diizinkan → jangan minta, biar IP yang handle
      }
      try {
        // Fallback chain akurasi: high (GPS satelit) → medium → low
        // (network/cell). Di dalam ruangan GPS satelit sering tidak fix
        // dalam 20 detik — network provider tetap akurat puluhan meter.
        for (final acc in const [
          LocationAccuracy.high,
          LocationAccuracy.medium,
          LocationAccuracy.low,
        ]) {
          try {
            final pos = await Geolocator.getCurrentPosition(
              locationSettings: LocationSettings(
                accuracy: acc,
                timeLimit: const Duration(seconds: 20),
              ),
            );
            return (pos.latitude, pos.longitude);
          } catch (e) {
            debugPrint('[location] getCurrentPosition $acc error: $e');
          }
        }
      } catch (e) {
        debugPrint('[location] current position error: $e');
      }
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null &&
            DateTime.now().difference(last.timestamp).inMinutes <= 10) {
          return (last.latitude, last.longitude);
        }
      } catch (e) {
        debugPrint('[location] last known error: $e');
      }
      return null;
    } catch (e) {
      debugPrint('[location] device position error: $e');
      return null;
    }
  }

  /// Variasi publik untuk register: ambil posisi device (tanpa dialog izin).
  Future<(double, double)?> tryDevicePositionForRegister() =>
      _tryDevicePosition();

  /// Minta izin lokasi secara eksplisit (dipanggil dari tombol "aktifkan
  /// lokasi presisi", BUKAN otomatis). Return true jika diberikan.
  Future<bool> requestPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    } catch (e) {
      debugPrint('[location] requestPermission error: $e');
      return false;
    }
  }

  /// Buka halaman izin app di Pengaturan sistem (untuk user yang pernah
  /// memilih "kira-kira" sehingga Android tidak menampilkan dialog lagi).
  Future<void> openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (e) {
      debugPrint('[location] openAppSettings error: $e');
    }
  }

  Future<void> _save(
    double lat,
    double lon,
    String source, [
    String? ip,
  ]) async {
    try {
      await _sb.rpc(
        'update_my_location',
        params: {
          'p_lat': lat,
          'p_lon': lon,
          'p_source': source,
          // Selalu kirim 4 argumen — server punya dua overload RPC
          // (3 & 4 arg), PostgREST error "ambiguous" kalau dipanggil 3.
          'p_ip': ip ?? '',
        },
      );
    } catch (e) {
      debugPrint('[location] save error: $e');
    }
  }

  /// Aktif/nonaktifkan berbagi lokasi untuk fitur "orang sekitar".
  Future<void> setShareLocation(bool value) async {
    final id = _sb.auth.currentUser?.id;
    if (id == null) return;
    try {
      await _sb.from('profiles').update({'share_location': value}).eq('id', id);
    } catch (e) {
      debugPrint('[location] setShareLocation error: $e');
    }
  }

  /// Ambil daftar orang sekitar dalam radius (km). Return list map:
  /// uid, nickname, gender, age, country, city, status, avatar,
  /// is_registered, last_seen, distance_km.
  Future<List<Map<String, dynamic>>> nearbyUsers(double radiusKm) async {
    final res = await _sb.rpc(
      'nearby_users',
      params: {'p_radius_km': radiusKm},
    );
    final list = res is List ? res : <dynamic>[];
    return list.cast<Map<String, dynamic>>();
  }
}
