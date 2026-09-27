import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:chatyuk/screens/admin_devices/widgets/location_route_map.dart';

/// Parser titik rute peta pergerakan admin (murni, tanpa context).
void main() {
  Map<String, dynamic> loc(double lat, double lon, String at,
          [String source = 'gps']) =>
      {'lat': lat, 'lon': lon, 'at': at, 'source': source};

  group('parseRoutePoints', () {
    test('urut waktu menaik walau input acak/terbalik', () {
      final out = parseRoutePoints([
        loc(-6.7, 108.4, '2026-09-25T13:27:22Z'),
        loc(-6.8, 108.5, '2026-09-25T13:25:44Z'),
      ]);
      expect(out.length, 2);
      expect(out.first.lat, -6.8);
      expect(out.last.lat, -6.7);
    });

    test('buang koordinat invalid (kosong/keluar rentang/tipe salah)', () {
      final out = parseRoutePoints([
        {'lat': '', 'lon': ''},
        {'lat': -91.0, 'lon': 108.0},
        {'lat': -6.0, 'lon': 181.0},
        {'lat': 'ngawur', 'lon': 'x'},
        {},
        loc(-6.7, 108.4, '2026-09-25T13:27:22Z'),
      ]);
      expect(out.length, 1);
      expect(out.first.latLng, const LatLng(-6.7, 108.4));
    });

    test('string numerik tetap diparse, source dipertahankan', () {
      final out = parseRoutePoints([
        {'lat': '-6.7', 'lon': '108.4', 'at': '', 'source': 'ip'},
      ]);
      expect(out.length, 1);
      expect(out.first.source, 'ip');
      expect(out.first.at, isNull);
    });

    test('cap 500: ambil 500 terbaru', () {
      final raw = [
        for (var i = 0; i < 600; i++)
          loc(-6.0 - i / 1000, 108.0,
              '2026-09-25T${(i ~/ 60).toString().padLeft(2, '0')}:${(i % 60).toString().padLeft(2, '0')}:00Z'),
      ];
      final out = parseRoutePoints(raw);
      expect(out.length, 500);
    });

    test('list kosong → kosong', () {
      expect(parseRoutePoints(const []), isEmpty);
    });
  });

  group('routeBounds', () {
    test('kotak pembatas benar', () {
      final b = routeBounds([
        const RoutePoint(lat: -6.8, lon: 108.4),
        const RoutePoint(lat: -6.7, lon: 108.5),
      ]);
      expect(b.south, -6.8);
      expect(b.north, -6.7);
      expect(b.west, 108.4);
      expect(b.east, 108.5);
    });

    test('titik tunggal → rentang minimum (zoom waras)', () {
      final b = routeBounds([const RoutePoint(lat: -6.7, lon: 108.4)]);
      expect(b.north - b.south, greaterThan(0));
      expect(b.east - b.west, greaterThan(0));
    });
  });

  group('googleMapsUrl', () {
    test('menyusun tautan Google Maps dengan lat,lon titik', () {
      expect(
        googleMapsUrl(const RoutePoint(lat: -6.7, lon: 108.4)),
        'https://www.google.com/maps/search/?api=1&query=-6.7,108.4',
      );
    });

    test('titik awal & akhir menghasilkan URL berbeda', () {
      final a = googleMapsUrl(const RoutePoint(lat: -6.8, lon: 108.4));
      final b = googleMapsUrl(const RoutePoint(lat: -6.7, lon: 108.5));
      expect(a, isNot(b));
      expect(a, contains('-6.8,108.4'));
      expect(b, contains('-6.7,108.5'));
    });
  });
}
