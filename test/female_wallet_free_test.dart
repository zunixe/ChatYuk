import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/widgets/points_onboard_items.dart';
import 'package:chatyuk/widgets/yukcoin_buckets_line.dart';

/// Perempuan gratis semua — hanya mendapat penghasilan:
/// - kartu saldo female selalu menampilkan Penghasilan (saldo utamanya),
///   tanpa Isi ulang, dan Bonus hanya bila > 0;
/// - onboarding female menyebut semua fitur gratis.
void main() {
  final s = S(isId: true);

  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('female: Penghasilan tampil walau 0, tanpa Isi ulang/Bonus', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        YukcoinBucketsText(
          s: s,
          bonus: 0,
          topup: 0,
          earned: 0,
          canTopup: false,
        ),
      ),
    );
    expect(find.textContaining(s.walletEarned), findsOneWidget);
    expect(find.textContaining(s.walletPaid), findsNothing);
    expect(find.textContaining(s.walletBonus), findsNothing);
  });

  testWidgets('male: Isi ulang + Bonus tampil', (tester) async {
    await tester.pumpWidget(
      wrap(
        YukcoinBucketsText(
          s: s,
          bonus: 0,
          topup: 10,
          earned: 0,
          showHint: false,
        ),
      ),
    );
    expect(find.textContaining(s.walletPaid), findsOneWidget);
    expect(find.textContaining(s.walletBonus), findsOneWidget);
  });

  testWidgets('onboarding female menyebut semua fitur gratis', (tester) async {
    await tester.pumpWidget(
      wrap(
        PointsOnboardItems(
          s: s,
          isFemale: true,
          callAudio: 10,
          callVideo: 20,
          matchFee: 2,
          withdrawMin: 1500,
        ),
      ),
    );
    expect(find.text(s.pointsOnboardFemaleAllFree), findsOneWidget);
  });

  test('string bebas biaya female bilingual & tanpa ajakan top-up', () {
    for (final isId in [true, false]) {
      final t = S(isId: isId);
      expect(t.btnExtendRoomFree.isNotEmpty, isTrue);
      expect(t.subscribeConfirmBodyFree('A').contains('YukCoin'), isFalse);
      expect(t.coinFemaleBlocked.isNotEmpty, isTrue);
      expect(t.callFreeMinutes(3, 30).contains('3/30'), isTrue);
    }
  });
}
