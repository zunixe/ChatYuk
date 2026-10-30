import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/models/random_match.dart';
import 'package:chatyuk/providers/riverpod/call_provider.dart';
import 'package:chatyuk/providers/riverpod/random_match_provider.dart';
import 'package:chatyuk/screens/random_match_screen.dart';
import 'package:chatyuk/services/random_match_service.dart';

class MockRandomMatchService extends Mock implements RandomMatchService {}

class _FakeCall extends CallNotifier {
  @override
  CallState build() => const CallState();
  @override
  Future<void> hangup() async {}
}

/// Layar radar: tombol Match → berubah jadi Batal saat mencari; avatar radar
/// memakai data nyata dari server (bukan angka palsu).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockRandomMatchService svc;

  setUp(() {
    svc = MockRandomMatchService();
    when(() => svc.leave()).thenAnswer((_) async {});
    when(() => svc.watchQueue()).thenAnswer((_) => const Stream<void>.empty());
  });

  /// Lepas widget tree sebelum test ditutup supaya `dispose()` (yang membatalkan
  /// timer radar) benar-benar berjalan — kalau tidak, framework menganggap
  /// timer 20 dtk masih pending.
  void disposeAfterTest(WidgetTester tester) {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 50));
    });
  }

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          randomMatchServiceProvider.overrideWithValue(svc),
          callProvider.overrideWith(() => _FakeCall()),
        ],
        child: const MaterialApp(home: RandomMatchScreen()),
      ),
    );
    await tester.pump();
    // Beri waktu timer kecil (avatar disk cache) selesai → tidak ada
    // "pending timer" saat test ditutup.
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('idle → tombol "Match" + jumlah online dari server', (
    tester,
  ) async {
    disposeAfterTest(tester);
    // Sample dikosongkan: avatar memicu I/O disk (timer) yang tidak relevan
    // dengan perilaku layar. Label jarak diuji di random_match_model_test.
    when(() => svc.stats()).thenAnswer(
      (_) async =>
          (waiting: 0, online: 7, sample: const <RandomRadarUser>[]),
    );
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Match'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Semua'), findsOneWidget);
  });

  testWidgets('tekan Match → "Batal" + jumlah penunggu', (tester) async {
    disposeAfterTest(tester);
    when(() => svc.stats()).thenAnswer(
      (_) async => (waiting: 3, online: 5, sample: const <RandomRadarUser>[]),
    );
    when(() => svc.join(any())).thenAnswer((_) async => {'status': 'waiting'});
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Match'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Batal'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('fitur belum aktif → snackbar, tetap idle', (tester) async {
    disposeAfterTest(tester);
    when(() => svc.stats()).thenAnswer(
      (_) async => (waiting: 0, online: 0, sample: const <RandomRadarUser>[]),
    );
    when(() => svc.join(any())).thenThrow(Exception('FEATURE_DISABLED'));
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Match'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Fitur belum aktif'), findsOneWidget);
    expect(find.text('Match'), findsOneWidget);
  });
}
