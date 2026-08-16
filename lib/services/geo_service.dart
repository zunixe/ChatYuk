import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

class GeoInfo {
  final String country;
  final String city;
  final String ipAddress;
  final double? lat;
  final double? lon;

  GeoInfo({
    required this.country,
    required this.city,
    required this.ipAddress,
    this.lat,
    this.lon,
  });
}

class GeoService {
  static const _countryNames = <String, String>{
    'ID': 'Indonesia',
    'MY': 'Malaysia',
    'SG': 'Singapore',
    'TH': 'Thailand',
    'PH': 'Philippines',
    'VN': 'Vietnam',
    'BN': 'Brunei',
    'MM': 'Myanmar',
    'KH': 'Cambodia',
    'LA': 'Laos',
    'TL': 'Timor-Leste',
  };

  // Fallback chain — kalau satu provider rate-limit/gagal, coba provider lain.
  static const _providers = <String>[
    'https://ipwho.is/',
    'https://ipapi.co/json/',
    'https://ip-api.com/json/',
  ];

  Future<GeoInfo?> detect() async {
    for (final url in _providers) {
      final info = await _tryProvider(url);
      if (info != null) return info;
    }
    return null;
  }

  /// Reverse-geocode koordinat GPS → negara + kota (nama Indonesia yang
  /// cocok dengan daftar regions.dart). Return null bila gagal.
  Future<GeoInfo?> detectByCoordinates(double lat, double lon) async {
    try {
      final places = await placemarkFromCoordinates(lat, lon);
      if (places.isEmpty) return null;
      final p = places.first;
      final country = _countryNames[p.isoCountryCode] ?? p.country ?? '';
      final city = (p.locality ?? p.subAdministrativeArea ?? p.administrativeArea ?? '');
      if (country.isEmpty) return null;
      return GeoInfo(
        country: country,
        city: city,
        ipAddress: '',
        lat: lat,
        lon: lon,
      );
    } catch (e) {
      debugPrint('[geo] detectByCoordinates error: $e');
      return null;
    }
  }

  /// Geolokasi IP TERTENTU (dipakai admin untuk user tanpa lat/lon login).
  /// ipwho.is & ip-api.com mendukung query IP spesifik.
  Future<GeoInfo?> detectByIp(String ip) async {
    for (final base in ['https://ipwho.is/', 'https://ip-api.com/json/']) {
      try {
        final info = await _tryProvider('$base$ip');
        if (info != null) return info;
      } catch (e) {
        debugPrint('[geo] detectByIp $ip error: $e');
      }
    }
    return null;
  }

  Future<GeoInfo?> _tryProvider(String url) async {
    try {
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['error'] == true) return null;
      if (data['status'] == 'fail') return null;

      // ipwho.is -> country_code/country/city/ip
      // ipapi.co -> country_code/country_name/city/ip
      // ip-api.com -> countryCode/country/city/query
      final code =
          (data['country_code'] as String?) ??
          (data['countryCode'] as String?) ??
          '';
      final country =
          _countryNames[code] ??
          (data['country'] as String?) ??
          (data['country_name'] as String?) ??
          '';
      final city = (data['city'] as String?) ?? '';
      final ip = (data['ip'] as String?) ?? (data['query'] as String?) ?? '';

      // Koordinat: ipwho.is & ipapi.co -> latitude/longitude,
      // ip-api.com -> lat/lon.
      double? toDouble(dynamic v) =>
          v is num ? v.toDouble() : double.tryParse('$v');
      final lat = toDouble(data['latitude']) ?? toDouble(data['lat']);
      final lon = toDouble(data['longitude']) ?? toDouble(data['lon']);

      if (country.isEmpty) return null;
      return GeoInfo(
        country: country,
        city: city,
        ipAddress: ip,
        lat: lat,
        lon: lon,
      );
    } catch (e) {
      debugPrint('[geo] detect error: $e');
      return null;
    }
  }
}
