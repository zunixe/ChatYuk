import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/config/gifts.dart';
import 'package:chatyuk/models/auth_data.dart';
import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/screens/point_history/widgets/yukcoin_how_to.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/services/points_service.dart';

import 'test_helper.dart';

class _MockAuthService extends Mock implements AuthService {}

class _MockPointsService extends Mock implements PointsService {}

class _TestAuth extends AuthNotifier {
  final UserModel? prof;
  _TestAuth(this.prof, AuthService svc) : super(authService: svc);
  @override
  AuthData build() => AuthData(profile: prof, uid: prof?.uid, loading: false);
  @override
  UserModel? get profile => prof;
}

UserModel _prof(String gender) => UserModel(
      uid: 'u-$gender',
      nickname: 'User',
      gender: gender,
      age: 21,
      country: 'Indonesia',
      city: 'Jakarta',
      ipAddress: '',
      status: 'online',
      avatar: '',
      isRegistered: true,
      loginAt: DateTime(2026, 1, 1),
      createdAt: DateTime(2026, 1, 1),
      lastSeen: DateTime(2026, 1, 1),
    );

/// Section "Cara dapat/pakai YukCoin" — isi beda per gender:
/// female = 4 sumber income (tanpa top-up/spend); male = top-up+bonus+gift
/// + section harga.
void main() {
  final s = S(isId: true);
  late _MockPointsService points;

  setUpAll(() async {
    await initSupabaseForTest();
  });

  setUp(() {
    points = _MockPointsService();
    when(() => points.watchOwnPoints()).thenAnswer((_) => Stream<int>.empty());
    when(() => points.watchEnabled()).thenAnswer((_) => Stream<bool>.empty());
    when(() => points.fetchEnabled()).thenAnswer((_) async => true);
    when(() => points.getWallet())
        .thenAnswer((_) async => <String, dynamic>{'bonus': 0, 'earned': 0, 'total': 0});
    when(() => points.meteredPricing()).thenAnswer((_) async => <String, dynamic>{});
    when(() => points.featureFlags()).thenAnswer((_) async => <String, dynamic>{});
  });

  Future<ProviderContainer> pump(WidgetTester t, String gender) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => _TestAuth(_prof(gender), _MockAuthService())),
        pointsProvider.overrideWith(() => PointsNotifier(service: points)),
      ],
    );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: YukcoinHowTo(s: s)),
          ),
        ),
      ),
    );
    await t.pump();
    return container;
  }

  testWidgets('female: 4 sumber income, tanpa top-up & tanpa section pakai',
      (t) async {
    final container = await pump(t, 'female');

    expect(find.text(s.yukcoinHowToEarn), findsOneWidget);
    expect(find.text(s.yukcoinEarnCallAudio), findsOneWidget);
    expect(find.text(s.yukcoinEarnCallVideo), findsOneWidget);
    expect(find.text(s.yukcoinEarnMatch), findsOneWidget);
    expect(find.text(s.yukcoinEarnGift), findsOneWidget);
    // Female tidak top-up dan tidak ditagih → section pakai tidak ada.
    expect(find.text(s.yukcoinEarnTopup), findsNothing);
    expect(find.text(s.yukcoinEarnWelcome), findsNothing);
    expect(find.text(s.yukcoinHowToSpend), findsNothing);
    container.dispose();
  });

  testWidgets('male: top-up + bonus + gift, plus section harga', (t) async {
    final container = await pump(t, 'male');

    expect(find.text(s.yukcoinEarnTopup), findsOneWidget);
    expect(find.text(s.yukcoinEarnWelcome), findsOneWidget);
    expect(find.text(s.yukcoinEarnGift), findsOneWidget);
    // Sumber income female tidak tampil untuk male.
    expect(find.text(s.yukcoinEarnCallAudio), findsNothing);
    expect(find.text(s.yukcoinEarnMatch), findsNothing);

    // Section "Cara pakai" muncul dengan 4 baris berharga.
    expect(find.text(s.yukcoinHowToSpend), findsOneWidget);
    expect(find.text(s.yukcoinFeatureCallAudio), findsOneWidget);
    expect(find.text(s.yukcoinFeatureCallVideo), findsOneWidget);
    expect(find.text(s.yukcoinFeatureMatch), findsOneWidget);
    expect(find.text(s.yukcoinFeatureGift), findsOneWidget);
    // Harga default: audio 6, video 20, match 2, rentang gift.
    expect(find.text('6'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('$kMatchFeeCoins'), findsOneWidget);
    expect(
      find.text('${kGiftCatalog.first.coins}–${kGiftCatalog.last.coins}'),
      findsOneWidget,
    );
    container.dispose();
  });
}
