import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/config/gifts.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/providers/riverpod/earnings_provider.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/screens/point_history/widgets/yukcoin_header.dart';
import 'package:chatyuk/screens/saldo_screen.dart';
import 'package:chatyuk/services/points_service.dart';
import 'package:chatyuk/widgets/gift_fly_overlay.dart';
import 'package:chatyuk/widgets/points_toast.dart';

import 'test_helper.dart';

class _MockPointsService extends Mock implements PointsService {}

class _FakeEarnings extends EarningsNotifier {
  final EarningsState s0;
  _FakeEarnings(this.s0);
  @override
  EarningsState build() => s0;
}

/// UI YukCoin: header saldo, layar Saldo, toast poin, overlay gift room.
void main() {
  final s = S(isId: true);

  setUpAll(() async {
    await initSupabaseForTest();
    await prewarmMediaForTest();
    GoogleFonts.config.allowRuntimeFetching = false;
    AppFonts.setLocal(AppFonts.systemKey);
  });

  tearDownAll(resetFontForTest);

  group('YukcoinHeader', () {
    testWidgets('saldo + label tampil; topup tersembunyi default', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: YukcoinHeader(s: s, total: 250)),
        ),
      );
      expect(find.text('250'), findsOneWidget);
      expect(find.text(s.yukcoinMyBalance), findsOneWidget);
      expect(find.text(s.yukcoinTopup), findsNothing);
    });

    testWidgets('showTopup → tombol Isi YukCoin tampil', (t) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: YukcoinHeader(s: s, total: 0, showTopup: true)),
        ),
      );
      expect(find.text(s.yukcoinTopup), findsOneWidget);
    });
  });

  group('SaldoScreen', () {
    late _MockPointsService points;

    setUp(() {
      points = _MockPointsService();
      when(() => points.watchOwnPoints())
          .thenAnswer((_) => Stream<int>.empty());
      when(() => points.watchEnabled())
          .thenAnswer((_) => Stream<bool>.empty());
      when(() => points.fetchEnabled()).thenAnswer((_) async => true);
      when(() => points.getWallet()).thenAnswer(
        (_) async => <String, dynamic>{'bonus': 0, 'earned': 0, 'total': 42},
      );
      when(() => points.meteredPricing())
          .thenAnswer((_) async => <String, dynamic>{});
      when(() => points.featureFlags())
          .thenAnswer((_) async => <String, dynamic>{});
    });

    Future<ProviderContainer> pumpSaldo(
      WidgetTester t,
      EarningsState st,
    ) async {
      final container = ProviderContainer(
        overrides: [
          earningsProvider.overrideWith(() => _FakeEarnings(st)),
          pointsProvider.overrideWith(() => PointsNotifier(service: points)),
        ],
      );
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SaldoScreen()),
        ),
      );
      await t.pump();
      return container;
    }

    testWidgets('data → saldo + rincian penghasilan + statistik', (t) async {
      // Viewport besar supaya seluruh ListView ter-build (stats di bawah
      // fold viewport 800×600 tidak dirender oleh lazy list).
      t.view.physicalSize = const Size(1080, 3200);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final container = await pumpSaldo(
        t,
        const EarningsState(
          loading: false,
          totalEarnings: 1200,
          weeklyEarnings: 300,
          todayEarnings: 80,
          privateCall: 600,
          matchCall: 200,
          message: 150,
          gift: 180,
          mission: 50,
          other: 20,
          videoCallCount: 7,
          videoCallSeconds: 3600,
          privateCallAnswered: 5,
          privateAnswerRate: 71,
          withdrawable: 42,
        ),
      );

      // Kartu saldo utama = saldo YukCoin (42 dari wallet mock).
      expect(find.text('42 🪙'), findsWidgets);
      // Rincian per sumber.
      expect(find.text('600 🪙'), findsOneWidget);
      expect(find.text('200 🪙'), findsOneWidget);
      expect(find.text('150 🪙'), findsOneWidget);
      expect(find.text('180 🪙'), findsOneWidget);
      // Statistik: 7x panggilan, 71% jawab.
      expect(find.textContaining('71'), findsWidgets);

      container.dispose();
    });

    testWidgets('loading → spinner; error → retry view', (t) async {
      var container = await pumpSaldo(t, const EarningsState());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      container.dispose();

      container = await pumpSaldo(
        t,
        const EarningsState(loading: false, error: 'x'),
      );
      final s2 = S(isId: true);
      expect(find.text(s2.saldoLoadFail), findsOneWidget);
      expect(find.text(s2.btnRetry), findsOneWidget);
      container.dispose();
    });
  });

  group('PointsToast', () {
    testWidgets('pesan tampil lalu auto-dismiss setelah animasi', (t) async {
      var dismissed = 0;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                PointsToast(message: '+5 YukCoin', onDismiss: () => dismissed++),
              ],
            ),
          ),
        ),
      );
      expect(find.text('+5 YukCoin'), findsOneWidget);
      // delay 1s + reverse 400ms → onDismiss.
      await t.pump(const Duration(seconds: 1));
      await t.pump(const Duration(milliseconds: 500));
      expect(dismissed, 1);
    });
  });

  group('GiftFlyController', () {
    // Catatan: window kombo memakai DateTime.now() (jam dinding) — tidak
    // bisa di-time-travel lewat fakeAsync, jadi diuji perilaku sinkron.
    test('push → fly masuk + kombo gift sama mengakumulasi + notify', () {
      final c = GiftFlyController();
      final g = kGiftCatalog.first;
      var notified = 0;
      c.addListener(() => notified++);
      c.push(g, 'Budi', 1);
      c.push(g, 'Budi', 1);
      expect(c.flies.length, 2);
      expect(c.activeCombo?.$1.id, g.id);
      expect(c.activeCombo?.$2, 2);
      expect(notified, 2);
    });

    test('flies dibatasi 5 — yang tertua dibuang', () {
      final c = GiftFlyController();
      final g = kGiftCatalog.first;
      for (var i = 0; i < 8; i++) {
        c.push(g, 'S$i', 1);
      }
      expect(c.flies.length, 5);
      // Id naik per push — hanya 5 terbaru yang tersisa.
      expect(c.flies.map((f) => f.id), [4, 5, 6, 7, 8]);
    });

    test('gift beda → kombo terpisah; kombo aktif = yang terbaru', () {
      final c = GiftFlyController();
      final g1 = kGiftCatalog.first;
      final g2 = kGiftCatalog.last;
      c.push(g1, 'A', 1);
      c.push(g2, 'A', 3);
      expect(c.activeCombo?.$1.id, g2.id);
      expect(c.activeCombo?.$2, 3);
    });
  });
}
