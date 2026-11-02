import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/models/auth_data.dart';
import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
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

/// ensureEnoughForCall — precheck call WAJIB pakai koin beli/penghasilan
/// (topup+earned). Sebelum migrasi 20261101190000 client cek saldo TOTAL,
/// jadi male yang hanya punya koin `bonus` lolos dialog lalu panggilannya
/// diputus server (charge_metered menolak bonus).
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
    when(() => points.meteredPricing()).thenAnswer((_) async => <String, dynamic>{});
    when(() => points.yukcoinV2Status()).thenAnswer(
      (_) async => <String, dynamic>{'active': false, 'ghost': false, 'extra_slots': 0},
    );
    when(() => points.featureFlags()).thenAnswer(
      (_) async => <String, dynamic>{
        'call_billing': {'published': true},
      },
    );
  });

  void wallet(int bonus, int topup, int earned) {
    when(() => points.getWallet()).thenAnswer(
      (_) async => <String, dynamic>{
        'bonus': bonus,
        'topup': topup,
        'earned': earned,
        'total': bonus + topup + earned,
      },
    );
  }

  Future<(ProviderContainer, BuildContext)> pump(
    WidgetTester t,
    String gender,
  ) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          () => _TestAuth(_prof(gender), _MockAuthService()),
        ),
        pointsProvider.overrideWith(() => PointsNotifier(service: points)),
      ],
    );
    late BuildContext ctx;
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(builder: (c) {
            ctx = c;
            return const SizedBox();
          }),
        ),
      ),
    );
    await container.read(pointsProvider.notifier).refreshMeteredPricing();
    return (container, ctx);
  }

  testWidgets('paidBalance = topup + earned, TIDAK menghitung bonus',
      (tester) async {
    wallet(500, 100, 50);
    final (container, _) = await pump(tester, 'male');
    await container.read(pointsProvider.notifier).refreshWallet();
    final st = container.read(pointsProvider);
    expect(st.paidBalance, 150);
    expect(st.points, 650);
    expect(st.bonusBalance, 500);
    container.dispose();
  });

  testWidgets('male bonus-only → ensureEnoughForCall false (dialog top-up)',
      (tester) async {
    wallet(500, 0, 0);
    final (container, ctx) = await pump(tester, 'male');
    final ok = await container
        .read(pointsProvider.notifier)
        .ensureEnoughForCall(ctx, 'audio', true);
    expect(ok, isFalse);
    // Dialog "koin tidak cukup" benar-benar tampil.
    await tester.pump();
    expect(find.text(s.callNeedCoinTitle), findsOneWidget);
    await tester.tap(find.text('Nanti'));
    await tester.pumpAndSettle();
    container.dispose();
  });

  testWidgets('male ber-koin beli → ensureEnoughForCall true', (tester) async {
    wallet(500, 100, 50);
    final (container, ctx) = await pump(tester, 'male');
    final ok = await container
        .read(pointsProvider.notifier)
        .ensureEnoughForCall(ctx, 'audio', true);
    expect(ok, isTrue);
    expect(find.text(s.callNeedCoinTitle), findsNothing);
    container.dispose();
  });

  testWidgets('female 0 koin → true (server gratiskan 30 menit/hari)',
      (tester) async {
    wallet(0, 0, 0);
    final (container, ctx) = await pump(tester, 'female');
    final ok = await container
        .read(pointsProvider.notifier)
        .ensureEnoughForCall(ctx, 'audio', true);
    expect(ok, isTrue);
    container.dispose();
  });
}
