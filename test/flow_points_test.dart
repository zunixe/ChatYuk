import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/providers/points_provider.dart';
import 'package:chatyuk/services/points_service.dart';

// Alur kritis 2: fitur koin → klaim milestone 5 mnt → service 1×.
// Hermetic: PointsService di-mock, tanpa network.

class MockPointsService extends Mock implements PointsService {}

void main() {
  final s = S(isId: true);

  testWidgets('klaim online 5 mnt dari UI memanggil service sekali', (
    tester,
  ) async {
    final service = MockPointsService();
    when(
      () => service.oneTimeBonus(any(), any()),
    ).thenAnswer((_) async => 999);
    when(
      () => service.watchOwnPoints(),
    ).thenAnswer((_) => Stream<int>.empty());
    when(() => service.getWallet()).thenAnswer(
      (_) async => <String, dynamic>{'bonus': 0, 'earned': 0, 'total': 50},
    );
    final provider = PointsProvider(service: service);
    provider.setOnlineSecondsForTest(300);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<PointsProvider>.value(
          value: provider,
          child: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () =>
                    context.read<PointsProvider>().debugClaimOnlineBonus(),
                child: Text(s.btnSave),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    verify(() => service.oneTimeBonus('online_5min', 5)).called(1);
    provider.dispose();
  });
}
