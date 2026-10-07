import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/services/points_service.dart';

import 'test_helper.dart';

// Alur kritis 2: fitur koin → bonus online DIHAPUS (overhaul 2026-10) →
// tidak ada klaim ke service. Hermetic: PointsService di-mock, tanpa network.

class MockPointsService extends Mock implements PointsService {}

void main() {
  final s = S(isId: true);

  setUpAll(() async {
    await initSupabaseForTest();
  });

  MockPointsService newService({required bool enabled}) {
    final service = MockPointsService();
    when(() => service.oneTimeBonus(any(), any())).thenAnswer((_) async => 999);
    when(() => service.watchOwnPoints()).thenAnswer((_) => Stream<int>.empty());
    when(() => service.getWallet()).thenAnswer(
      (_) async => <String, dynamic>{'bonus': 0, 'earned': 0, 'total': 50},
    );
    when(() => service.meteredPricing())
        .thenAnswer((_) async => <String, dynamic>{});
    when(() => service.featureFlags())
        .thenAnswer((_) async => <String, dynamic>{});
    when(() => service.fetchEnabled()).thenAnswer((_) async => enabled);
    return service;
  }

  Future<ProviderContainer> pump(WidgetTester tester, PointsService service) async {
    final container = ProviderContainer(
      overrides: [
        pointsProvider.overrideWith(() => PointsNotifier(service: service)),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () =>
                    ProviderScope.containerOf(context, listen: false)
                        .read(pointsProvider.notifier)
                        .debugClaimOnlineBonus(),
                child: Text(s.btnSave),
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('bonus online dihapus → service TIDAK dipanggil walau 300 dtk', (
    tester,
  ) async {
    final service = newService(enabled: true);
    final c = await pump(tester, service);
    final provider = c.read(pointsProvider.notifier);
    await provider.refreshEnabled();
    provider.setOnlineSecondsForTest(300);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    verifyNever(() => service.oneTimeBonus(any(), any()));
    c.dispose();
  });

  testWidgets('flag OFF → juga tidak memanggil service', (tester) async {
    final service = newService(enabled: false);
    final c = await pump(tester, service);
    final provider = c.read(pointsProvider.notifier);
    await provider.refreshEnabled();
    provider.setOnlineSecondsForTest(300);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    verifyNever(() => service.oneTimeBonus(any(), any()));
    c.dispose();
  });
}
