import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/points_provider.dart';
import 'package:chatyuk/services/points_service.dart';

import 'test_helper.dart';

class MockPointsService extends Mock implements PointsService {}

void main() {
  late MockPointsService service;
  late PointsProvider provider;

  setUpAll(() async {
    await initSupabaseForTest();
  });

  setUp(() {
    service = MockPointsService();
    // Poin naik (50 → 999) supaya wrapper klaim mengembalikan true.
    when(() => service.oneTimeBonus(any(), any()))
        .thenAnswer((_) async => 999);
    when(() => service.watchOwnPoints())
        .thenAnswer((_) => Stream<int>.empty());
    provider = PointsProvider(service: service);
  });

  tearDown(() {
    provider.dispose();
  });

  group('milestone online', () {
    test('300 dtk → klaim online_5min sekali', () async {
      provider.setOnlineSecondsForTest(300);
      await provider.debugClaimOnlineBonus();
      verify(() => service.oneTimeBonus('online_5min', 5)).called(1);
    });

    test('di bawah threshold tidak klaim', () async {
      provider.setOnlineSecondsForTest(299);
      await provider.debugClaimOnlineBonus();
      verifyNever(() => service.oneTimeBonus(any(), any()));
    });

    test('klaim idempoten — dobel picu tetap sekali', () async {
      provider.setOnlineSecondsForTest(4000);
      await provider.debugClaimOnlineBonus();
      await provider.debugClaimOnlineBonus();
      verify(() => service.oneTimeBonus('online_5min', 5)).called(1);
      verify(() => service.oneTimeBonus('online_30min', 10)).called(1);
      verify(() => service.oneTimeBonus('online_60min', 15)).called(1);
    });

    test('reset membuka klaim ulang', () async {
      provider.setOnlineSecondsForTest(300);
      await provider.debugClaimOnlineBonus();
      provider.resetOnlineTrackers();
      provider.setOnlineSecondsForTest(300);
      await provider.debugClaimOnlineBonus();
      verify(() => service.oneTimeBonus('online_5min', 5)).called(2);
    });

    test('batas 120 menit memakai ambang 7200', () async {
      provider.setOnlineSecondsForTest(7199);
      await provider.debugClaimOnlineBonus();
      verifyNever(() => service.oneTimeBonus('online_120min', 15));
      provider.setOnlineSecondsForTest(7200);
      await provider.debugClaimOnlineBonus();
      verify(() => service.oneTimeBonus('online_120min', 15)).called(1);
    });
  });
}
