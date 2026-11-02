import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/services/mission_progress_service.dart';
import 'package:chatyuk/services/points_service.dart';

import 'test_helper.dart';

class MockPointsService extends Mock implements PointsService {}

class MockMissionProgress extends Mock implements MissionProgressService {}

void main() {
  late MockPointsService service;
  late MockMissionProgress missionProgress;
  late ProviderContainer container;
  late PointsNotifier provider;

  setUpAll(() async {
    await initSupabaseForTest();
  });

  setUp(() {
    service = MockPointsService();
    missionProgress = MockMissionProgress();
    when(() => service.watchOwnPoints()).thenAnswer((_) => Stream<int>.empty());
    when(() => service.watchEnabled()).thenAnswer((_) => Stream<bool>.empty());
    when(() => service.fetchEnabled()).thenAnswer((_) async => true);
    when(() => service.getWallet()).thenAnswer(
      (_) async => <String, dynamic>{'bonus': 0, 'earned': 0, 'total': 50},
    );
    when(() => service.meteredPricing())
        .thenAnswer((_) async => <String, dynamic>{});
    when(() => service.featureFlags())
        .thenAnswer((_) async => <String, dynamic>{});
    when(() => missionProgress.updateProgress(any(), increment: any(named: 'increment')))
        .thenAnswer((_) async {});
    container = ProviderContainer(
      overrides: [
        pointsProvider.overrideWith(
          () => PointsNotifier(service: service, missionProgress: missionProgress),
        ),
      ],
    );
    addTearDown(container.dispose);
    provider = container.read(pointsProvider.notifier);
  });

  group('passthrough belanja YukCoin', () {



    test('leaderboard/pointHistory/activityLeaderboard → args diteruskan',
        () async {
      when(() => service.leaderboard('weekly', limit: 10, offset: 5))
          .thenAnswer((_) async => {'rows': []});
      when(() => service.activityLeaderboard('weekly'))
          .thenAnswer((_) async => {'rows': []});
      when(() => service.pointHistory(limit: 20, offset: 4))
          .thenAnswer((_) async => []);
      await provider.leaderboard('weekly', limit: 10, offset: 5);
      await provider.activityLeaderboard('weekly');
      await provider.pointHistory(limit: 20, offset: 4);
      verify(() => service.leaderboard('weekly', limit: 10, offset: 5)).called(1);
      verify(() => service.activityLeaderboard('weekly')).called(1);
      verify(() => service.pointHistory(limit: 20, offset: 4)).called(1);
    });
  });

  group('trackMission', () {


    test('trackMission → MissionProgressService.updateProgress', () async {
      provider.trackMission('chat_sent', increment: 3);
      // updateProgress dipanggil async (unawaited) — beri waktu microtask.
      await Future<void>.delayed(Duration.zero);
      verify(() => missionProgress.updateProgress('chat_sent', increment: 3))
          .called(1);
    });
  });

  group('ensureEnoughForCall', () {
    Future<void> enableBilling() async {
      when(() => service.fetchEnabled()).thenAnswer((_) async => true);
      when(() => service.featureFlags()).thenAnswer(
        (_) async => <String, dynamic>{
          'call_billing': {'published': true},
        },
      );
      // Feature flags di-load di konstruktor — bangun provider BARU supaya
      // flag ke-load; alternatifnya pakai refreshMeteredPricing+flags.
      container.dispose();
      container = ProviderContainer(
        overrides: [
          pointsProvider.overrideWith(
            () => PointsNotifier(service: service, missionProgress: missionProgress),
          ),
        ],
      );
      provider = container.read(pointsProvider.notifier);
      await provider.refreshEnabled();
      await provider.refreshMeteredPricing();
      await provider.refreshWallet();
    }

    testWidgets('koin cukup → true, tanpa dialog', (tester) async {
      // 2026-11-01: server hanya menerima koin beli/penghasilan — saldo
      // "cukup" harus topup/earned, bukan bonus.
      when(() => service.getWallet()).thenAnswer(
        (_) async => <String, dynamic>{
          'bonus': 0, 'topup': 500, 'earned': 0, 'total': 500},
      );
      await enableBilling();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              provider.ensureEnoughForCall(ctx, 'video', true);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Koin beli 500 ≥ tarif video → tidak ada AlertDialog.
      expect(find.byType(AlertDialog), findsNothing);

      // Matikan timer periodik provider sebelum tree dibuang.
      container.dispose();
    });

    testWidgets('bonus-only (total cukup) → dialog topup MUNCUL', (tester) async {
      // Regresi 2026-11-01: dulu cek saldo TOTAL → male bonus-only lolos
      // dialog lalu call diputus server (charge_metered menolak bonus).
      when(() => service.getWallet()).thenAnswer(
        (_) async => <String, dynamic>{
          'bonus': 500, 'topup': 0, 'earned': 0, 'total': 500},
      );
      await enableBilling();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              provider.ensureEnoughForCall(ctx, 'video', true);
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // Total 500 ≥ tarif, tapi koin beli 0 → dialog harus muncul.
      expect(find.byType(AlertDialog), findsOneWidget);
      container.dispose();
    });

    testWidgets('koin kurang → false + dialog topup', (tester) async {
      // ensureEnoughForCall memanggil refreshWallet → saldo dari getWallet.
      when(() => service.getWallet()).thenAnswer(
        (_) async => <String, dynamic>{'bonus': 0, 'earned': 0, 'total': 0},
      );
      await enableBilling();

      var result = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              provider.ensureEnoughForCall(ctx, 'video', true).then(
                (v) => result = v,
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(result, false);
      // Dialog "butuh YukCoin" muncul dengan tombol topup.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Isi YukCoin'), findsOneWidget);

      container.dispose();
    });
  });
}
