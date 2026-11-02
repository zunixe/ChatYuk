import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/screens/missions/widgets/bonus_widgets.dart';

/// Widget halaman Bonus (grid sign-in + baris tugas) — presentasional murni,
/// tanpa provider.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('BonusDayCard', () {
    testWidgets('future (state 0): label + reward, tanpa centang', (t) async {
      await t.pumpWidget(
        host(const BonusDayCard(day: 1, coins: 25, state: 0, dayLabel: 'Hari 1')),
      );
      expect(find.text('Hari 1'), findsOneWidget);
      expect(find.text('+25'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(find.byIcon(Icons.monetization_on_rounded), findsOneWidget);
    });

    testWidgets('hari ini (state 1): centang tampil', (t) async {
      await t.pumpWidget(
        host(const BonusDayCard(day: 3, coins: 35, state: 1, dayLabel: 'Hari 3')),
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.text('+35'), findsOneWidget);
    });

    testWidgets('claimed (state 2): centang tampil', (t) async {
      await t.pumpWidget(
        host(const BonusDayCard(day: 2, coins: 30, state: 2, dayLabel: 'Hari 2')),
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });
  });

  group('kStreakRewards', () {
    test('7 hari siklus, nilai sesuai server', () {
      expect(kStreakRewards, [25, 30, 35, 40, 45, 50, 100]);
    });
  });

  group('BonusTaskRow', () {
    testWidgets('belum klaim + bisa → tombol aksi memanggil onClaim',
        (t) async {
      var taps = 0;
      await t.pumpWidget(
        host(
          BonusTaskRow(
            title: 'Login harian',
            progressLabel: '1/1',
            rewardCoins: 25,
            claimed: false,
            claimLabel: 'Klaim',
            onClaim: () => taps++,
          ),
        ),
      );
      expect(find.text('Login harian'), findsOneWidget);
      expect(find.text('1/1'), findsOneWidget);
      expect(find.text('+25'), findsOneWidget);
      await t.tap(find.text('Klaim'));
      expect(taps, 1);
    });

    testWidgets('claimed → ikon centang, tanpa tombol', (t) async {
      await t.pumpWidget(
        host(
          BonusTaskRow(
            title: 'Login harian',
            progressLabel: '',
            rewardCoins: 25,
            claimed: true,
            claimLabel: 'Klaim',
            onClaim: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('locked → ikon gembok, tanpa tombol', (t) async {
      await t.pumpWidget(
        host(
          BonusTaskRow(
            title: 'Misi mingguan',
            progressLabel: '',
            rewardCoins: 100,
            claimed: false,
            locked: true,
            claimLabel: 'Klaim',
            onClaim: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('tanpa onClaim & tanpa lock → panah navigasi', (t) async {
      await t.pumpWidget(
        host(
          const BonusTaskRow(
            title: 'Buka profil',
            progressLabel: '',
            rewardCoins: 10,
            claimed: false,
            claimLabel: 'Klaim',
          ),
        ),
      );
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}
