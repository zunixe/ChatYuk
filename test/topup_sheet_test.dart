import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/providers/riverpod/locale_provider.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/providers/riverpod/topup_provider.dart';
import 'package:chatyuk/screens/point_history/widgets/topup_sheet.dart';
import 'package:chatyuk/services/points_service.dart';
import 'package:chatyuk/services/topup_service.dart';

import 'package:google_fonts/google_fonts.dart';

import 'package:chatyuk/config/fonts.dart';

import 'test_helper.dart';

class _MockTopupService extends Mock implements TopupService {}

class _MockPointsService extends Mock implements PointsService {}

/// Sheet pilih paket topup — daftar dari TopupService (Play) atau fallback
/// `listTopupPackages` (server). Tombol beli aktif hanya bila Billing siap.
void main() {
  final sEn = S(isId: false);

  // Sheet mengikuti bahasa app (AppLocale) — test memeriksa teks Inggris.
  setUp(() => AppLocale.lang = 'en');
  tearDown(() => AppLocale.lang = 'id');

  setUpAll(() async {
    await initSupabaseForTest();
    GoogleFonts.config.allowRuntimeFetching = false;
    AppFonts.setLocal(AppFonts.systemKey);
  });

  tearDownAll(resetFontForTest);

  late _MockTopupService topup;
  late _MockPointsService points;

  setUp(() {
    topup = _MockTopupService();
    points = _MockPointsService();
    when(() => points.watchOwnPoints()).thenAnswer((_) => Stream<int>.empty());
    when(() => points.watchEnabled()).thenAnswer((_) => Stream<bool>.empty());
    when(() => points.fetchEnabled()).thenAnswer((_) async => true);
    when(() => points.getWallet()).thenAnswer(
      (_) async => <String, dynamic>{'bonus': 0, 'earned': 0, 'total': 0},
    );
    when(() => points.meteredPricing())
        .thenAnswer((_) async => <String, dynamic>{});
    when(() => points.featureFlags())
        .thenAnswer((_) async => <String, dynamic>{});
    when(() => points.listTopupPackages())
        .thenAnswer((_) async => <Map<String, dynamic>>[]);
    when(() => topup.packages).thenReturn(const []);
    when(() => topup.available).thenReturn(false);
    when(() => topup.buy(any())).thenAnswer((_) async {});
  });

  Future<ProviderContainer> pump(WidgetTester t) async {
    final container = ProviderContainer(
      overrides: [
        topupProvider.overrideWith((_) => TopupNotifier(topup)),
        pointsProvider.overrideWith(() => PointsNotifier(service: points)),
      ],
    );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => FilledButton(
                onPressed: () => showTopupSheet(ctx, sEn),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    return container;
  }

  List<Map<String, dynamic>> pkgs() => [
        {
          'coins': 100,
          'price_idr': 15000,
          'play_product_id': 'coins_100',
          'bonus_label': '+10%',
        },
        {
          'coins': 500,
          'price_idr': 69000,
          'play_product_id': 'coins_500',
        },
      ];

  testWidgets('paket tampil: koin + harga Rp berformat + label bonus',
      (t) async {
    when(() => topup.packages).thenReturn(pkgs());
    final container = await pump(t);

    expect(find.text('100'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.text('Rp 15.000'), findsOneWidget);
    expect(find.text('Rp 69.000'), findsOneWidget);
    expect(find.text('+10%'), findsOneWidget);

    container.dispose();
  });

  testWidgets('billing tidak tersedia → notice + tile tidak menjalankan buy',
      (t) async {
    when(() => topup.packages).thenReturn(pkgs());
    when(() => topup.available).thenReturn(false);
    final container = await pump(t);

    // Notice "segera hadir" (canBuy=false).
    expect(find.text(sEn.yukcoinTopupSoon), findsWidgets);

    await t.tap(find.text('100'));
    await t.pumpAndSettle();
    verifyNever(() => topup.buy(any()));

    container.dispose();
  });

  testWidgets('billing siap → tap paket memanggil buy(productId) + tutup',
      (t) async {
    when(() => topup.packages).thenReturn(pkgs());
    when(() => topup.available).thenReturn(true);
    final container = await pump(t);

    await t.tap(find.text('500'));
    await t.pumpAndSettle();

    verify(() => topup.buy('coins_500')).called(1);
    // Sheet tertutup.
    expect(find.text('500'), findsNothing);

    container.dispose();
  });

  testWidgets('tanpa paket (service & server kosong) → empty state', (t) async {
    when(() => topup.packages).thenReturn(const []);
    final container = await pump(t);
    // Biarkan _load() selesai.
    await t.pumpAndSettle();

    expect(find.text(sEn.yukcoinTopupSoon), findsWidgets);
    expect(find.text('Rp'), findsNothing);

    container.dispose();
  });

  testWidgets('service kosong → fallback listTopupPackages server', (t) async {
    when(() => topup.packages).thenReturn(const []);
    when(() => points.listTopupPackages()).thenAnswer((_) async => pkgs());
    final container = await pump(t);
    await t.pumpAndSettle();

    verify(() => points.listTopupPackages()).called(1);
    expect(find.text('100'), findsOneWidget);

    container.dispose();
  });
}
