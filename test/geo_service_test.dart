import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chatyuk/services/geo_service.dart';

/// Jalankan body dengan `http.Client` mock (dipakai `http.get` GeoService).
Future<T> withClient<T>(
  Future<T> Function() body,
  MockClient client,
) =>
    http.runWithClient(body, () => client);

void main() {
  group('GeoService.detect — parsing tiap provider', () {
    test('ipwho.is (country_code/city/ip/latitude/longitude)', () async {
      final client = MockClient((req) async {
        expect(req.url.host, 'ipwho.is');
        return http.Response(
          jsonEncode({
            'ip': '1.2.3.4',
            'country_code': 'ID',
            'country': 'Indonesia',
            'city': 'Jakarta',
            'latitude': -6.2,
            'longitude': 106.8,
          }),
          200,
        );
      });
      final info = await withClient(() => GeoService().detect(), client);
      expect(info, isNotNull);
      expect(info!.country, 'Indonesia');
      expect(info.city, 'Jakarta');
      expect(info.ipAddress, '1.2.3.4');
      expect(info.lat, -6.2);
      expect(info.lon, 106.8);
    });

    test('ipapi.co (country_code/country_name/city/ip)', () async {
      // Provider pertama gagal → fallback ke ipapi.co.
      var call = 0;
      final client = MockClient((req) async {
        call++;
        if (req.url.host == 'ipwho.is') {
          return http.Response('{"error": true}', 200);
        }
        expect(req.url.host, 'ipapi.co');
        return http.Response(
          jsonEncode({
            'ip': '5.6.7.8',
            'country_code': 'MY',
            'country_name': 'Malaysia',
            'city': 'Kuala Lumpur',
            'latitude': 3.1,
            'longitude': 101.7,
          }),
          200,
        );
      });
      final info = await withClient(() => GeoService().detect(), client);
      expect(call, greaterThanOrEqualTo(2));
      expect(info, isNotNull);
      expect(info!.country, 'Malaysia');
      expect(info.city, 'Kuala Lumpur');
    });

    test('ip-api.com (countryCode/query/lat/lon)', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'ip-api.com') {
          return http.Response(
            jsonEncode({
              'status': 'success',
              'countryCode': 'SG',
              'country': 'Singapore',
              'city': 'Singapore',
              'query': '9.9.9.9',
              'lat': 1.35,
              'lon': 103.8,
            }),
            200,
          );
        }
        return http.Response('{}', 200);
      });
      final info = await withClient(
        () => GeoService().detectByIp('9.9.9.9'),
        client,
      );
      expect(info, isNotNull);
      expect(info!.country, 'Singapore');
      expect(info.ipAddress, '9.9.9.9');
    });

    test('semua provider gagal → null', () async {
      final client = MockClient((req) async => http.Response('{}', 500));
      final info = await withClient(() => GeoService().detect(), client);
      expect(info, isNull);
    });

    test('kode negara dipetakan ke nama Indonesia resmi', () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({'country_code': 'VN', 'city': 'Hanoi', 'ip': 'x'}),
          200,
        ),
      );
      final info = await withClient(() => GeoService().detect(), client);
      expect(info!.country, 'Vietnam');
    });

    test('country_code tak dikenal → pakai nama country apa adanya', () async {
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({
            'country_code': 'US',
            'country': 'United States',
            'city': 'NY',
            'ip': 'x',
          }),
          200,
        ),
      );
      final info = await withClient(() => GeoService().detect(), client);
      expect(info!.country, 'United States');
    });

    test('respons tanpa negara → null (provider dianggap gagal)', () async {
      final client = MockClient(
        (req) async => http.Response(jsonEncode({'ip': 'x', 'city': 'y'}), 200),
      );
      final info = await withClient(() => GeoService().detect(), client);
      expect(info, isNull);
    });

    test('respons bukan JSON valid → tidak crash, fallback/null', () async {
      final client = MockClient(
        (req) async => http.Response('<html>not json</html>', 200),
      );
      final info = await withClient(() => GeoService().detect(), client);
      expect(info, isNull);
    });

    test('status fail ip-api → provider dilewati', () async {
      final client = MockClient((req) async {
        if (req.url.host == 'ip-api.com') {
          return http.Response('{"status":"fail"}', 200);
        }
        return http.Response('{"error":true}', 200);
      });
      final info = await withClient(() => GeoService().detect(), client);
      expect(info, isNull);
    });
  });
}
