import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/models/random_match.dart';
import 'package:chatyuk/providers/riverpod/call_provider.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/providers/riverpod/random_match_provider.dart';
import 'package:chatyuk/screens/random_call_screen.dart';
import 'package:chatyuk/services/points_service.dart';

import 'test_helper.dart';

class _MockPointsService extends Mock implements PointsService {}

/// Sesi call asli (tanpa init media) — renderer belum terinisialisasi →
/// RTCVideoView merender Container kosong, aman untuk widget test.
class _FakeCall extends CallNotifier {
  final CallSession session;
  _FakeCall(this.session);

  @override
  CallState build() => CallState(
        activeCallId: session.callId,
        activeSession: session,
        activeMode: CallMode.fullscreen,
        activeChatId: 'random_${session.callId}',
      );

  @override
  Future<void> hangup() async {}
}

class _FakeMatch extends RandomMatchNotifier {
  @override
  RandomMatchState build() => const RandomMatchState(
        phase: RandomMatchPhase.inCall,
        callId: 'c1',
        partner: RandomPartner(uid: 'u-mia', nickname: 'Mia'),
      );
}

/// Counter YukCoin di bar atas layar match: angka = sisa saldo, "−N" =
/// terpakai call ini; disembunyikan bila sistem koin dimatikan admin.
void main() {
  setUpAll(() async {
    await initSupabaseForTest();
    await prewarmMediaForTest();
  });

  late _MockPointsService points;
  late CallSession session;

  setUp(() {
    points = _MockPointsService();
    when(() => points.watchOwnPoints()).thenAnswer((_) => Stream<int>.empty());
    when(() => points.watchEnabled()).thenAnswer((_) => Stream<bool>.empty());
    when(() => points.fetchEnabled()).thenAnswer((_) async => true);
    when(() => points.getWallet()).thenAnswer(
      (_) async => <String, dynamic>{'bonus': 0, 'earned': 0, 'total': 50},
    );
    when(() => points.meteredPricing())
        .thenAnswer((_) async => <String, dynamic>{});
    when(() => points.featureFlags())
        .thenAnswer((_) async => <String, dynamic>{});
    session = CallSession(
      callId: 'c1',
      remoteUid: 'u-mia',
      remoteName: 'Mia',
      callType: 'video',
      isCaller: true,
    );
  });

  Future<ProviderContainer> pump(WidgetTester t) async {
    final container = ProviderContainer(
      overrides: [
        randomMatchProvider.overrideWith(() => _FakeMatch()),
        callProvider.overrideWith(() => _FakeCall(session)),
        pointsProvider.overrideWith(() => PointsNotifier(service: points)),
      ],
    );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: RandomCallScreen()),
      ),
    );
    await t.pump();
    // Flush retry avatar (3× jeda 300ms saat foto kosong) supaya tidak ada
    // timer pending saat test ditutup.
    await t.pump(const Duration(seconds: 1));
    return container;
  }

  testWidgets('counter koin tampil: saldo live di bar atas', (t) async {
    final container = await pump(t);

    expect(find.byIcon(Icons.monetization_on_outlined), findsOneWidget);
    expect(find.text('50'), findsOneWidget);

    container.dispose();
  });

  testWidgets('billing jalan → "saldo (−terpakai)"', (t) async {
    final container = await pump(t);

    session.debugSetBilling(charged: 2);
    await t.pump();

    expect(find.text('50 (−2)'), findsOneWidget);

    container.dispose();
  });

  testWidgets('saldo berubah → counter ikut (billing tick)', (t) async {
    final container = await pump(t);
    final notifier = container.read(pointsProvider.notifier);

    notifier.setPoints(37);
    await t.pump();

    expect(find.text('37'), findsOneWidget);

    container.dispose();
  });

  testWidgets('sistem koin OFF → counter disembunyikan', (t) async {
    when(() => points.fetchEnabled()).thenAnswer((_) async => false);
    final container = await pump(t);
    await t.pump();

    expect(find.byIcon(Icons.monetization_on_outlined), findsNothing);
    expect(find.text('50'), findsNothing);

    container.dispose();
  });
}
