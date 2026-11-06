import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';


import 'package:chatyuk/models/mission.dart';
import 'package:chatyuk/providers/riverpod/locale_provider.dart';
import 'package:chatyuk/providers/riverpod/missions_provider.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/screens/missions_screen.dart';
import 'package:chatyuk/services/points_service.dart';

class MockPointsService extends Mock implements PointsService {}
/// Tanggal hari ini zona WIB (server memakai Asia/Jakarta) — format yang
/// sama dengan _todayWib di MissionsScreen. Jangan hardcode: test harus
/// tetap hijau setiap hari.
String _todayWib() {
  final wib = DateTime.now().toUtc().add(const Duration(hours: 7));
  return '${wib.year.toString().padLeft(4, '0')}-'
      '${wib.month.toString().padLeft(2, '0')}-'
      '${wib.day.toString().padLeft(2, '0')}';
}

class _FakePoints extends PointsNotifier {
  _FakePoints() : super(service: MockPointsService());

  @override
  PointsState build() => const PointsState();

  static int signInCalls = 0;

  @override
  Future<({int streak, int bonus})> claimDailyLogin() async {
    signInCalls++;
    return (streak: 1, bonus: 25);
  }
}

MissionsState _state({
  String gender = 'male',
  int streak = 0,
  String? lastLoginDate,
  List<Mission> main = const [],
  List<Mission> daily = const [],
  int totalCoins = 0,
}) => MissionsState(
      mainMissions: main,
      dailyMissions: daily,
      totalCoins: totalCoins,
      loading: false,
      loginStreak: streak,
      lastLoginDate: lastLoginDate,
      gender: gender,
    );

Mission _m(
  String key, {
  bool daily = false,
  bool claimed = false,
  int target = 3,
  int reward = 10,
  String? title,
}) => Mission(
      id: 0,
      missionKey: key,
      title: title ?? key,
      description: '',
      category: '',
      targetValue: target,
      targetUnit: 'x',
      rewardCoins: reward,
      isDaily: daily,
      progress: 0,
      claimed: claimed,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => _FakePoints.signInCalls = 0);

  Future<void> pump(
    WidgetTester tester, {
    required MissionsState state,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          missionsProvider.overrideWith(() => _FakeMissions(state)),
          pointsProvider.overrideWith(_FakePoints.new),
          localeProvider.overrideWith(() => _FakeLocale()),
        ],
        child: const MaterialApp(home: MissionsScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('male → grid sign-in 7 hari + tombol Sign in tampil', (
    tester,
  ) async {
    await pump(tester, state: _state(gender: 'male', streak: 3));
    // 7 kartu hari + tombol Sign in.
    expect(find.text('Hari 1'), findsOneWidget);
    expect(find.text('Hari 7'), findsOneWidget);
    expect(find.text('Masuk Harian'), findsOneWidget);
  });

  testWidgets('female → seksi sign-in disembunyikan', (tester) async {
    await pump(tester, state: _state(gender: 'female', streak: 2));
    expect(find.text('Hari 1'), findsNothing);
    expect(find.text('Masuk Harian'), findsNothing);
    // Seksi tugas tetap ada.
    expect(find.text('Tugas Pemula'), findsOneWidget);
  });

  testWidgets('tap Sign in → claimDailyLogin terpanggil', (tester) async {
    await pump(tester, state: _state(gender: 'male', streak: 0));
    await tester.tap(find.text('Masuk Harian'));
    await tester.pump();
    expect(_FakePoints.signInCalls, 1);
  });

  testWidgets('sudah klaim hari ini → tombol disabled (Sudah klaim)', (
    tester,
  ) async {
    await pump(
      tester,
      state: _state(gender: 'male', streak: 2, lastLoginDate: _todayWib()),
    );
    expect(find.text('Sudah klaim hari ini'), findsOneWidget);
    await tester.tap(find.text('Sudah klaim hari ini'));
    await tester.pump();
    expect(_FakePoints.signInCalls, 0);
  });

  testWidgets('misi canClaim → tombol Klaim tampil', (tester) async {
    final m = _m('like_posts')..isCompleted = true;
    await pump(tester, state: _state(main: [m]));
    expect(find.text('Klaim'), findsOneWidget);
  });

  testWidgets('female: nyonya → counter di header, bukan baris misi', (
    tester,
  ) async {
    final nyonya = _m('nyonya_1000', target: 1000, title: 'Misi Nyonya');
    await pump(
      tester,
      state: _state(gender: 'female', main: [nyonya, _m('like_posts')]),
    );
    // Judul misi tidak jadi baris; progresnya jadi counter di header,
    // counter "x/y selesai" tetap ada (di samping judul).
    expect(find.text('Misi Nyonya'), findsNothing);
    expect(find.text('0/1000'), findsOneWidget);
    expect(find.text('0/2 selesai'), findsOneWidget);
    // Baris misi lain tetap tampil.
    expect(find.text('like_posts'), findsOneWidget);
  });

  testWidgets('male: tanpa nyonya → counter "x/y selesai" tetap', (
    tester,
  ) async {
    final done = _m('a')..isCompleted = true;
    await pump(tester, state: _state(gender: 'male', main: [done, _m('b')]));
    expect(find.text('1/2 selesai'), findsOneWidget);
  });

  testWidgets('female: nyonya penuh → Klaim +reward di header', (
    tester,
  ) async {
    _FakeMissions.claimedKeys.clear();
    final nyonya = _m('nyonya_1000', target: 1000, reward: 100)
      ..progress = 1000
      ..isCompleted = true;
    await pump(tester, state: _state(gender: 'female', main: [nyonya]));
    expect(find.text('Klaim +100'), findsOneWidget);
    await tester.tap(find.text('Klaim +100'));
    await tester.pump();
    expect(_FakeMissions.claimedKeys, contains('nyonya_1000'));
  });
}

class _FakeMissions extends MissionsNotifier {
  final MissionsState _state;
  _FakeMissions(this._state);

  static final List<String> claimedKeys = [];

  @override
  MissionsState build() => _state;

  @override
  Future<bool> claimReward(String missionKey) async {
    claimedKeys.add(missionKey);
    return true;
  }
}

class _FakeLocale extends LocaleNotifier {
  @override
  LocaleState build() => const LocaleState('id');
}
