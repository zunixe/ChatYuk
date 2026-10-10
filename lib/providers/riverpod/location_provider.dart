import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/geo_service.dart';
export '../../services/geo_service.dart' show GeoInfo, GeoService;
import '../../services/location_service.dart';
export '../../services/location_service.dart'
    show LocationService, DeviceFix, NearbyPlace;

/// Lokasi + geolokasi (IP/GPS) — action-only, wrapper service.
/// Migrasi dari ChangeNotifier (0 notifyListeners) → Provider.
class LocationNotifier {
  final LocationService location;
  final GeoService geo;
  LocationNotifier({LocationService? location, GeoService? geo})
      : location = location ?? LocationService(),
        geo = geo ?? GeoService();

  Future<String?> updateMyLocation() => location.updateMyLocation();
  Future<DeviceFix?> tryDevicePositionForRegister() =>
      location.tryDevicePositionForRegister();
  Future<(double, double)?> lastKnownPosition() => location.lastKnownPosition();
  Future<bool> requestPermission() => location.requestPermission();
  Future<void> openSettings() => location.openSettings();
  Future<void> setShareLocation(bool value) => location.setShareLocation(value);
  Future<List<Map<String, dynamic>>> nearbyUsers(double radiusKm,
          {int limit = 50, int offset = 0}) =>
      location.nearbyUsers(radiusKm, limit: limit, offset: offset);
  Future<(double, double, int)?> precisePosition() => location.precisePosition();
  Future<List<NearbyPlace>> nearbyPlaces(double lat, double lng,
          {int radiusM = 400, int limit = 8}) =>
      location.nearbyPlaces(lat, lng, radiusM: radiusM, limit: limit);

  Future<GeoInfo?> detect() => geo.detect();
  Future<GeoInfo?> detectByCoordinates(double lat, double lon) =>
      geo.detectByCoordinates(lat, lon);
  Future<GeoInfo?> detectByIp(String ip) => geo.detectByIp(ip);
}

final locationProvider = Provider<LocationNotifier>((_) => LocationNotifier());
