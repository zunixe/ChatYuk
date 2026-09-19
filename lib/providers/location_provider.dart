import 'package:flutter/foundation.dart';

import '../services/geo_service.dart';
export '../services/geo_service.dart' show GeoInfo, GeoService;
import '../services/location_service.dart';
export '../services/location_service.dart' show LocationService;

/// Provider lokasi + geolokasi (IP/GPS) — screen tidak import `services/`.
class LocationProvider extends ChangeNotifier {
  final LocationService location;
  final GeoService geo;
  LocationProvider({LocationService? location, GeoService? geo})
      : location = location ?? LocationService(),
        geo = geo ?? GeoService();

  Future<String?> updateMyLocation() => location.updateMyLocation();
  Future<(double, double)?> tryDevicePositionForRegister() =>
      location.tryDevicePositionForRegister();
  Future<(double, double)?> lastKnownPosition() => location.lastKnownPosition();
  Future<bool> requestPermission() => location.requestPermission();
  Future<void> openSettings() => location.openSettings();
  Future<void> setShareLocation(bool value) => location.setShareLocation(value);
  Future<List<Map<String, dynamic>>> nearbyUsers(double radiusKm) =>
      location.nearbyUsers(radiusKm);

  Future<GeoInfo?> detect() => geo.detect();
  Future<GeoInfo?> detectByCoordinates(double lat, double lon) =>
      geo.detectByCoordinates(lat, lon);
  Future<GeoInfo?> detectByIp(String ip) => geo.detectByIp(ip);
}
