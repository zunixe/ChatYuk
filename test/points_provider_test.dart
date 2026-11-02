import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/services/points_service.dart';

import 'test_helper.dart';

class MockPointsService extends Mock implements PointsService {}

void main() {
  late MockPointsService service;
  late ProviderContainer container;
  late PointsNotifier provider;

  setUpAll(() async {
    await initSupabaseForTest();
  });

  setUp(() {
    service = MockPointsService();
    when(() => service.watchOwnPoints()).thenAnswer((_) => Stream<int>.empty());
    when(() => service.getWallet()).thenAnswer(
      (_) async => <String, dynamic>{'bonus': 0, 'earned': 0, 'total': 50},
    );
    // Overhaul coin: harga fitur + feature flags (dipanggil di konstruktor).
    when(() => service.meteredPricing())
        .thenAnswer((_) async => <String, dynamic>{});
    when(() => service.featureFlags())
        .thenAnswer((_) async => <String, dynamic>{});
    container = ProviderContainer(
      overrides: [
        pointsProvider.overrideWith(() => PointsNotifier(service: service)),
      ],
    );
    addTearDown(container.dispose);
    provider = container.read(pointsProvider.notifier);
  });

  group('milestone online', () {
    // Overhaul coin 2026-10: bonus online DIHAPUS — tidak ada klaim ke service.
    setUp(() async {
      when(() => service.fetchEnabled()).thenAnswer((_) async => true);
      when(() => service.meteredPricing()).thenAnswer((_) async => <String, dynamic>{});
      when(() => service.featureFlags()).thenAnswer((_) async => <String, dynamic>{});
      await provider.refreshEnabled();
    });

    test('300 dtk → TIDAK klaim (faucet dihapus)', () async {
      provider.setOnlineSecondsForTest(300);
      await provider.debugClaimOnlineBonus();
    });

    test('4000 dtk → TIDAK klaim apa pun', () async {
      provider.setOnlineSecondsForTest(4000);
      await provider.debugClaimOnlineBonus();
    });

    test('resetOnlineTrackers tidak memanggil service', () async {
      provider.setOnlineSecondsForTest(300);
      provider.resetOnlineTrackers();
      await provider.debugClaimOnlineBonus();
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
      container.listen(pointsProvider, (_, _) => notified++);
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
      final c = ProviderContainer(overrides: [
        pointsProvider.overrideWith(() => PointsNotifier(service: service)),
      ]);
      final p = c.read(pointsProvider.notifier);
      addTearDown(c.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 150));

      var notified = 0;
      c.listen(pointsProvider, (_, _) => notified++);
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
        final c = ProviderContainer(overrides: [
          pointsProvider.overrideWith(() => PointsNotifier(service: service)),
        ]);
        final p = c.read(pointsProvider.notifier);
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
        c.dispose();
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
        final c = ProviderContainer(overrides: [
          pointsProvider.overrideWith(() => PointsNotifier(service: service)),
        ]);
        final p = c.read(pointsProvider.notifier);
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
        c.dispose();
      });
      ctrl.close();
    });
  });


  group('bonus klaim & unlock (provider)', () {
    setUp(() async {
      when(() => service.fetchEnabled()).thenAnswer((_) async => true);
      await provider.refreshEnabled();
    });

    test('claimDailyLogin → RPC + saldo ikut total respons', () async {
      when(() => service.dailyLoginBonus()).thenAnswer(
        (_) async => {'streak': 1, 'bonus': 25, 'total': 75},
      );
      final r = await provider.claimDailyLogin();
      verify(() => service.dailyLoginBonus()).called(1);
      expect(provider.points, 75);
      expect(r.streak, 1);
      expect(r.bonus, 25);
    });

    test('claimDailyLogin OFF → diam', () async {
      when(() => service.fetchEnabled()).thenAnswer((_) async => false);
      await provider.refreshEnabled();

      await provider.claimDailyLogin();

      verifyNever(() => service.dailyLoginBonus());
    });

    test('newChatBonus naik → true; gagal → false', () async {
      when(() => service.newChatBonus('u9')).thenAnswer((_) async => 55);
      expect(await provider.newChatBonus('u9'), isTrue);
      expect(provider.points, 55);

      when(() => service.newChatBonus('u9')).thenThrow(Exception('x'));
      expect(await provider.newChatBonus('u9'), isFalse);
    });

    test('newChatBonus OFF → false', () async {
      when(() => service.fetchEnabled()).thenAnswer((_) async => false);
      await provider.refreshEnabled();

      expect(await provider.newChatBonus('u9'), isFalse);
      verifyNever(() => service.newChatBonus(any()));
    });




    test('subscribeCreator → map + wallet refresh', () async {
      when(() => service.subscribeCreator(any(), periods: any(named: 'periods')))
          .thenAnswer((_) async => {'ok': true});
      when(() => service.getWallet()).thenAnswer(
        (_) async => <String, dynamic>{'bonus': 1, 'earned': 2, 'total': 60},
      );

      final res = await provider.subscribeCreator('creator', periods: 2);

      expect(res['ok'], isTrue);
      expect(provider.points, 60);
    });

  });

  group('chat charge/refund', () {
    setUp(() async {
      when(() => service.fetchEnabled()).thenAnswer((_) async => true);
      await provider.refreshEnabled();
    });

    test('deduct berhasil mengembalikan saldo baru dan notify', () async {
      when(() => service.deductChatPoint('image')).thenAnswer((_) async => 49);
      var notified = 0;
      container.listen(pointsProvider, (_, _) => notified++);

      final result = await provider.deductBeforeSend('image');

      expect(result, 49);
      expect(provider.points, 49);
      expect(notified, 1);
      verify(() => service.deductChatPoint('image')).called(1);
    });

    test('teks gratis → deduct/refund tanpa RPC (2026-10-31)', () async {
      // deduct_chat_point no-op untuk 'text' di server — provider
      // short-circuit lokal supaya tidak tembak RPC per pesan.
      expect(await provider.deductBeforeSend('text'), 50);
      await provider.refundChatPoint('text');
      verifyNever(() => service.deductChatPoint(any()));
      verifyNever(() => service.refundChatPoint(any()));
      expect(provider.points, 50);
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
      when(() => service.refundChatPoint('image')).thenAnswer((_) async => 51);

      await provider.refundChatPoint('image');

      expect(provider.points, 51);
      verify(() => service.refundChatPoint('image')).called(1);
    });

    test('refund error tidak melempar dan saldo tetap', () async {
      when(
        () => service.refundChatPoint('image'),
      ).thenThrow(Exception('network offline'));

      await expectLater(provider.refundChatPoint('image'), completes);
      expect(provider.points, 50);
    });

    test('charge dan refund disabled tidak memanggil service', () async {
      when(() => service.fetchEnabled()).thenAnswer((_) async => false);
      await provider.refreshEnabled();

      expect(await provider.deductBeforeSend('image'), 50);
      await provider.refundChatPoint('image');

      verifyNever(() => service.deductChatPoint(any()));
      verifyNever(() => service.refundChatPoint(any()));
      expect(provider.points, 50);
    });

    test('sebelum flag terkonfirmasi (mentah true) → tetap charge', () async {
      // Kontrak a5f2e19/deduct: `_enabled` mentah default true supaya tidak
      // ada jendela gratis sebelum fetchEnabled selesai. Server mengembalikan
      // saldo tanpa potong saat OFF, jadi aman.
      final freshC = ProviderContainer(overrides: [
        pointsProvider.overrideWith(() => PointsNotifier(service: service)),
      ]);
      final fresh = freshC.read(pointsProvider.notifier);
      addTearDown(freshC.dispose);
      when(() => service.deductChatPoint('image')).thenAnswer((_) async => 49);

      expect(await fresh.deductBeforeSend('image'), 49);
      verify(() => service.deductChatPoint('image')).called(1);
    });
  });

  group('harga server (room pricing + photo costs)', () {
    test('refreshRoomPricing memetakan semua field + notify', () async {
      // join_paid sengaja dikirim server (kolom masih ada) tapi provider
      // TIDAK lagi menyimpannya — join room gratis di server (charge 0).
      when(() => service.roomPricing()).thenAnswer((_) async => {
            'create_paid': 200,
            'create_pw_paid': 250,
            'join_paid': 10,
            'extend_paid': 80,
            'multiplier': 5,
          });
      var notified = 0;
      container.listen(pointsProvider, (_, _) => notified++);

      await provider.refreshRoomPricing();

      expect(provider.roomCreatePaid, 200);
      expect(provider.roomCreatePwPaid, 250);
      expect(provider.roomExtendPaid, 80);
      expect(provider.bonusMultiplier, 5);
      expect(notified, 1);
    });

    test('refreshRoomPricing error → nilai lama bertahan', () async {
      when(() => service.roomPricing()).thenThrow(Exception('offline'));
      await provider.refreshRoomPricing();
      expect(provider.roomCreatePaid, 100);
      expect(provider.bonusMultiplier, 3);
    });

  });

  group('harga fitur berbayar (metered)', () {
    test('callCostPerMin: audio/video dari server; default 6/20', () async {
      // default sebelum fetch
      expect(provider.callCostPerMin('audio'), 6);
      expect(provider.callCostPerMin('video'), 20);
      // setelah fetch dari server
      when(() => service.meteredPricing()).thenAnswer((_) async => {
            'call_audio_cost_per_min': 8,
            'call_video_cost_per_min': 25,
            'filter_gender_cost': 20,
            'nearby_cost': 30,
          });
      when(() => service.featureFlags()).thenAnswer((_) async => {});
      await provider.refreshMeteredPricing();
      expect(provider.callCostPerMin('audio'), 8);
      expect(provider.callCostPerMin('video'), 25);
      // filter_gender_cost / nearby_cost: field mati — server masih
      // mengirim tapi provider tak lagi menyimpan (fitur gratis).
    });

    test('featurePublished dari flag server', () async {
      when(() => service.meteredPricing())
          .thenAnswer((_) async => <String, dynamic>{});
      when(() => service.featureFlags()).thenAnswer((_) async => {
            'call_billing': {'published': true},
            'nearby_paid': {'published': false},
          });
      await provider.refreshMeteredPricing();
      expect(provider.callBillingPublished, isTrue);
      expect(provider.featurePublished('nearby_paid'), isFalse);
    });



    test('claimWelcomeBonus → coins + refreshWallet', () async {
      when(() => service.claimWelcomeBonus(
            installId: any(named: 'installId'),
            kind: any(named: 'kind'),
          )).thenAnswer((_) async => {'granted': true, 'coins': 100});
      when(() => service.getWallet()).thenAnswer(
        (_) async => <String, dynamic>{'bonus': 100, 'earned': 0, 'total': 100},
      );
      final coins = await provider.claimWelcomeBonus(
        installId: 'drm-abc',
        kind: 'anon',
      );
      expect(coins, 100);
      expect(provider.points, 100);
    });

    test('claimWelcomeBonus sudah diklaim → 0', () async {
      when(() => service.claimWelcomeBonus(
            installId: any(named: 'installId'),
            kind: any(named: 'kind'),
          )).thenAnswer((_) async => {'granted': false, 'coins': 0});
      final coins = await provider.claimWelcomeBonus(
        installId: 'drm-abc',
        kind: 'anon',
      );
      expect(coins, 0);
    });
  });

  group('visibilitas topup (topupPathOpen)', () {
    test('default: tanpa flag → tertutup', () {
      expect(provider.playTopupPublished, isFalse);
      expect(provider.yukcoinV2Active, isFalse);
      expect(provider.topupPathOpen, isFalse);
    });

    test('publish play_topup → terbuka', () async {
      when(() => service.meteredPricing())
          .thenAnswer((_) async => <String, dynamic>{});
      when(() => service.featureFlags()).thenAnswer(
        (_) async => {
          'play_topup': {'published': true},
        },
      );
      await provider.refreshMeteredPricing();
      expect(provider.playTopupPublished, isTrue);
      expect(provider.topupPathOpen, isTrue);
    });

    test('toggle YukCoin v2 aktif → topup terbuka', () async {
      when(() => service.yukcoinV2Status()).thenAnswer(
        (_) async => <String, dynamic>{'active': true},
      );
      await provider.refreshYukcoinV2();
      expect(provider.yukcoinV2Active, isTrue);
      expect(provider.topupPathOpen, isTrue);
    });

    test('toggle YukCoin v2 non-aktif & tanpa publish → tertutup', () async {
      when(() => service.yukcoinV2Status()).thenAnswer(
        (_) async => <String, dynamic>{'active': false},
      );
      await provider.refreshYukcoinV2();
      expect(provider.yukcoinV2Active, isFalse);
      expect(provider.topupPathOpen, isFalse);
    });

    test('yukcoinV2Status error → tetap tertutup (aman)', () async {
      when(() => service.yukcoinV2Status()).thenThrow(Exception('offline'));
      await provider.refreshYukcoinV2();
      expect(provider.yukcoinV2Active, isFalse);
      expect(provider.topupPathOpen, isFalse);
    });
  });
}
