import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/admin_provider.dart';
import 'package:chatyuk/services/admin_service.dart';

import 'supabase_test_client.dart';

class MockAdminService extends Mock implements AdminService {}

/// Sebaran geografis (Ringkasan admin): negara → kota.
/// Mengunci pemetaan service → provider (cache + state).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockAdminService svc;

  setUp(() => svc = MockAdminService());

  AdminProvider prov() => AdminProvider(service: svc, sb: fakeSupabaseClient());

  test('fetchCountryStats → tersimpan + geoLoaded true', () async {
    when(() => svc.fetchCountryStats()).thenAnswer(
      (_) async => [
        {'country': 'Indonesia', 'count': 42, 'registered': 30},
        {'country': 'Malaysia', 'count': 5, 'registered': 2},
      ],
    );
    final p = prov();
    expect(p.countryStats, isEmpty);
    await p.fetchCountryStats();
    expect(p.geoLoaded, isTrue);
    expect(p.countryStats.length, 2);
    expect(p.countryStats.first['country'], 'Indonesia');
    p.dispose();
  });

  test('fetchCountryStats di-cache (panggil kedua tanpa RPC lagi)', () async {
    when(() => svc.fetchCountryStats()).thenAnswer((_) async => []);
    final p = prov();
    await p.fetchCountryStats();
    await p.fetchCountryStats();
    verify(() => svc.fetchCountryStats()).called(1);
    p.dispose();
  });

  test('fetchCityStats → per negara + cache', () async {
    when(() => svc.fetchCityStats('Indonesia')).thenAnswer(
      (_) async => [
        {'city': 'Jakarta', 'count': 54, 'registered': 26},
        {'city': 'Bandung', 'count': 36, 'registered': 26},
      ],
    );
    final p = prov();
    final a = await p.fetchCityStats('Indonesia');
    expect(a.length, 2);
    expect(a.first['city'], 'Jakarta');
    final b = await p.fetchCityStats('Indonesia');
    expect(b.length, 2);
    verify(() => svc.fetchCityStats('Indonesia')).called(1); // cache
    p.dispose();
  });

  test('fetchCityStats gagal → list kosong, tidak crash', () async {
    when(() => svc.fetchCityStats(any()))
        .thenThrow(Exception('network'));
    final p = prov();
    expect(await p.fetchCityStats('X'), isEmpty);
    p.dispose();
  });
}
