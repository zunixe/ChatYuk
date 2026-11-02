import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/providers/riverpod/locale_provider.dart';
import 'package:chatyuk/providers/riverpod/my_level_provider.dart';
import 'package:chatyuk/screens/my_level_screen.dart';

import 'test_helper.dart';

/// Notifier palsu — state tetap, tanpa Supabase (build di-override).
class TestMyLevel extends MyLevelNotifier {
  final MyLevelState fixed;
  TestMyLevel(this.fixed);
  @override
  MyLevelState build() => fixed;
  @override
  Future<void> refresh() async {}
}

MyLevelState state({
  int level = 0,
  int cumulative = 0,
  int? nextLevel = 1,
  int? nextAt = 700,
  int remaining = 700,
  List<Map<String, dynamic>>? ladder,
  List<Map<String, dynamic>> justRewarded = const [],
}) {
  final lad = ladder ??
      [
        for (var i = 0; i <= 10; i++)
          {
            'level': i,
            'topup_coins': const [0, 700, 2000, 5000, 12000, 25000, 55000,
              120000, 250000, 500000, 1000000][i],
            'reward_coins': const [0, 50, 100, 150, 200, 300, 400, 500, 750,
              1000, 2000][i],
          },
      ];
  return MyLevelState(
    loading: false,
    level: level,
    cumulative: cumulative,
    nextLevel: nextLevel,
    nextAt: nextAt,
    remaining: remaining,
    ladder: lad,
    justRewarded: justRewarded,
  );
}

/// Regresi UI My Level: kartu hero (level + progress + caption top-up),
/// tab Privileges per level, tabel Aturan Level, dan CTA top-up.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    AppFonts.setLocal(AppFonts.systemKey);
    await initSupabaseForTest();
  });

  Future<void> pump(
    WidgetTester tester, {
    required MyLevelState fixed,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: ProviderContainer(
          overrides: [
            localeProvider.overrideWith(() => _LocaleId()),
            myLevelProvider.overrideWith(() => TestMyLevel(fixed)),
          ],
        ),
        child: const MaterialApp(home: MyLevelScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Lv.0: caption ajak top-up 700 ke Lv.1, tab Lv.0 tanpa privilege',
    (tester) async {
      await pump(tester, fixed: state());
      expect(find.text('Lv.0'), findsWidgets);
      expect(find.text('Top up 700 🪙 lagi untuk naik ke Lv.1'), findsOneWidget);
      // Tab Lv.0 aktif → teks kosong privilege.
      expect(find.text('Belum ada privilege di level ini — top up untuk mulai'),
          findsOneWidget);
      // Tabel rule memuat tangga (700 & 1.000.000).
      expect(find.text('700'), findsOneWidget);
      expect(find.text('1.000.000'), findsOneWidget);
    });

  testWidgets('Lv.2: privilege Badge + Bonus Koin +100, baris tabel tersorot',
    (tester) async {
      await pump(tester, fixed: state(level: 2, cumulative: 2000,
          nextLevel: 3, nextAt: 5000, remaining: 3000));
      expect(find.text('Top up 3.000 🪙 lagi untuk naik ke Lv.3'), findsOneWidget);
      expect(find.text('Badge Level'), findsOneWidget);
      expect(find.text('Bonus Koin'), findsOneWidget);
      expect(find.text('Dapat +100 🪙 saat naik ke level ini'), findsOneWidget);
    });

  testWidgets('Lv.10 (maks): caption level tertinggi, tanpa next',
    (tester) async {
      await pump(tester, fixed: state(level: 10, cumulative: 1000000,
          nextLevel: null, nextAt: null, remaining: 0));
      expect(find.text('Kamu di level tertinggi 🔥'), findsOneWidget);
    });

  testWidgets('reward baru tampil di kartu hero', (tester) async {
    await pump(tester, fixed: state(level: 1, cumulative: 700,
        nextLevel: 2, nextAt: 2000, remaining: 1300,
        justRewarded: const [
          {'level': 1, 'coins': 50},
        ]));
    expect(find.text('Naik level dapat +50 🪙'), findsOneWidget);
  });
}

class _LocaleId extends LocaleNotifier {
  @override
  LocaleState build() => const LocaleState('id');
}
