import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    when(() => service.oneTimeBonus(any(), any())).thenAnswer((_) async => 999);
    when(() => service.watchOwnPoints()).thenAnswer((_) => Stream<int>.empty());
    when(() => service.getWallet()).thenAnswer(
      (_) async => <String, dynamic>{'bonus': 0, 'earned': 0, 'total': 50},
    );
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

  group('wallet bucket (RPC get_wallet)', () {
    test('bonus/earned/total dipetakan ke getter', () async {
      when(() => service.getWallet()).thenAnswer(
        (_) async => <String, dynamic>{'bonus': 7, 'earned': 3, 'total': 60},
      );
      await provider.refreshWallet();
      expect(provider.bonusBalance, 7);
      expect(provider.earnedBalance, 3);
      expect(provider.points, 60);
    });

    test(
      'key hilang/null → bonus & earned 0, total tak mereset saldo lama',
      () async {
        when(() => service.getWallet()).thenAnswer(
          (_) async => <String, dynamic>{'bonus': 7, 'earned': 3, 'total': 60},
        );
        await provider.refreshWallet();
        when(() => service.getWallet()).thenAnswer(
          (_) async => <String, dynamic>{'bonus': null, 'earned': null},
        );
        await provider.refreshWallet();
        expect(provider.bonusBalance, 0);
        expect(provider.earnedBalance, 0);
        expect(
          provider.points,
          60,
          reason: 'total null → saldo lama dipertahankan, bukan reset 0',
        );
      },
    );

    test('getWallet error → nilai lama bertahan, tidak throw', () async {
      when(() => service.getWallet()).thenAnswer(
        (_) async => <String, dynamic>{'bonus': 12, 'earned': 4, 'total': 66},
      );
      await provider.refreshWallet();
      when(() => service.getWallet()).thenThrow(Exception('offline'));
      await provider.refreshWallet();
      expect(provider.bonusBalance, 12);
      expect(provider.earnedBalance, 4);
      expect(provider.points, 66);
    });

    test('refreshWallet notify listener', () async {
      var notified = 0;
      provider.addListener(() => notified++);
      await provider.refreshWallet();
      expect(notified, 1);
    });
  });

  group('realtime poin + debounce wallet', () {
    // Catatan: saat konstruksi, provider men-subscribe ulang pada event auth
    // `initialSession` + mengambil rincian wallet. Tes di bawah menunggu
    // fase itu selesai dulu supaya hitungan panggilan deterministik.
    test('event stream poin memperbarui saldo + notify', () async {
      final ctrl = StreamController<int>.broadcast();
      when(() => service.watchOwnPoints()).thenAnswer((_) => ctrl.stream);
      final p = PointsProvider(service: service);
      addTearDown(p.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      var notified = 0;
      p.addListener(() => notified++);
      ctrl.add(120);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(p.points, 120);
      expect(notified, 1);
      await ctrl.close();
    });

    test('burst event → get_wallet dipanggil sekali (debounce 800ms)', () {
      var walletCalls = 0;
      when(() => service.getWallet()).thenAnswer((_) async {
        walletCalls++;
        return <String, dynamic>{'bonus': 1, 'earned': 2, 'total': 100};
      });
      final ctrl = StreamController<int>.broadcast();
      when(() => service.watchOwnPoints()).thenAnswer((_) => ctrl.stream);

      fakeAsync((async) {
        final p = PointsProvider(service: service);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        final base = walletCalls;
        expect(
          base,
          greaterThanOrEqualTo(1),
          reason: 'rincian awal diambil saat subscribe',
        );

        // Bonus online / bonus pesan memicu beberapa event beruntun.
        ctrl.add(60);
        ctrl.add(61);
        ctrl.add(62);
        async.flushMicrotasks();
        expect(p.points, 62, reason: 'saldo total ikut event terbaru');
        expect(walletCalls - base, 0, reason: 'belum lewat window debounce');

        // Lewat 800ms → satu RPC get_wallet, bucket bonus/earned ikut segar.
        async.elapse(const Duration(seconds: 2));
        expect(walletCalls - base, 1, reason: 'burst → tetap 1 RPC get_wallet');
        expect(p.bonusBalance, 1);
        expect(p.earnedBalance, 2);
        expect(p.points, 100, reason: 'total ikut rincian wallet terbaru');
        p.dispose();
      });
      ctrl.close();
    });

    test('event dengan nilai sama tidak memicu get_wallet ulang', () {
      var walletCalls = 0;
      when(() => service.getWallet()).thenAnswer((_) async {
        walletCalls++;
        return <String, dynamic>{'bonus': 0, 'earned': 0, 'total': 50};
      });
      final ctrl = StreamController<int>.broadcast();
      when(() => service.watchOwnPoints()).thenAnswer((_) => ctrl.stream);

      fakeAsync((async) {
        final p = PointsProvider(service: service);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        final base = walletCalls;
        expect(p.points, 50);

        ctrl.add(50); // sama dengan saldo sekarang → tak ada perubahan
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        expect(
          walletCalls,
          base,
          reason: 'nilai sama → tak perlu tarik bucket',
        );
        p.dispose();
      });
      ctrl.close();
    });
  });

  group('syncFromProfile', () {
    test('nilai beda → notify; sama → no-op', () {
      var notified = 0;
      provider.addListener(() => notified++);

      provider.syncFromProfile(75);
      expect(provider.points, 75);
      expect(notified, 1);

      provider.syncFromProfile(75);
      expect(notified, 1, reason: 'nilai sama tidak memicu rebuild');
    });
  });

  group('chat charge/refund', () {
    setUp(() async {
      when(() => service.fetchEnabled()).thenAnswer((_) async => true);
      await provider.refreshEnabled();
    });

    test('deduct berhasil mengembalikan saldo baru dan notify', () async {
      when(() => service.deductChatPoint('text')).thenAnswer((_) async => 49);
      var notified = 0;
      provider.addListener(() => notified++);

      final result = await provider.deductBeforeSend('text');

      expect(result, 49);
      expect(provider.points, 49);
      expect(notified, 1);
      verify(() => service.deductChatPoint('text')).called(1);
    });

    test('saldo tidak cukup mengembalikan -1 tanpa mengubah saldo', () async {
      when(() => service.deductChatPoint('image')).thenThrow(
        PostgrestException(
          message: 'Not enough points',
          code: 'P0001',
          details: null,
          hint: null,
        ),
      );

      final result = await provider.deductBeforeSend('image');

      expect(result, -1);
      expect(provider.points, 50);
    });

    test('error RPC mengembalikan -2 tanpa mengubah saldo', () async {
      when(
        () => service.deductChatPoint('voice'),
      ).thenThrow(Exception('network offline'));

      final result = await provider.deductBeforeSend('voice');

      expect(result, -2);
      expect(provider.points, 50);
    });

    test('refund memperbarui saldo dan memanggil service', () async {
      when(() => service.refundChatPoint('text')).thenAnswer((_) async => 51);

      await provider.refundChatPoint('text');

      expect(provider.points, 51);
      verify(() => service.refundChatPoint('text')).called(1);
    });

    test('refund error tidak melempar dan saldo tetap', () async {
      when(
        () => service.refundChatPoint('text'),
      ).thenThrow(Exception('network offline'));

      await expectLater(provider.refundChatPoint('text'), completes);
      expect(provider.points, 50);
    });

    test('charge dan refund disabled tidak memanggil service', () async {
      when(() => service.fetchEnabled()).thenAnswer((_) async => false);
      await provider.refreshEnabled();

      expect(await provider.deductBeforeSend('text'), 50);
      await provider.refundChatPoint('text');

      verifyNever(() => service.deductChatPoint(any()));
      verifyNever(() => service.refundChatPoint(any()));
      expect(provider.points, 50);
    });
  });
}
