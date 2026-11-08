import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/widgets/points_onboard_items.dart';

/// Kunci isi popup onboarding YukCoin per gender (tidak boleh miss info):
/// - female TIDAK dapat bonus selamat datang & tidak bisa kirim gift
///   (server: credit_welcome_bonus → female_no_bonus; send_gift menolak
///   female) → tak ada baris bonus gratis / kirim hadiah / top-up.
/// - male melihat harga + bonus selamat datang, tanpa info withdraw.
void main() {
  for (final isId in [true, false]) {
    final s = S(isId: isId);
    final lang = isId ? 'id' : 'en';

    Widget host(bool isFemale) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PointsOnboardItems(
            s: s,
            isFemale: isFemale,
            callAudio: 10,
            callVideo: 20,
            matchFee: 10,
            withdrawMin: 1500,
          ),
        ),
      ),
    );

    testWidgets('female ($lang): tanpa bonus gratis & kirim hadiah', (
      tester,
    ) async {
      await tester.pumpWidget(host(true));
      expect(find.text(s.pointsOnboardMaleWelcome), findsNothing);
      expect(find.text(s.pointsOnboardMaleGift(10, 1000)), findsNothing);
      expect(find.text(s.pointsOnboardMaleSub), findsNothing);
      expect(find.text(s.pointsOnboardFemaleSub), findsOneWidget);
      expect(find.text(s.pointsOnboardFemaleGift), findsOneWidget);
      expect(find.text(s.pointsOnboardFemaleWithdraw(1500)), findsOneWidget);
      // Tidak ada teks yang menjanjikan koin gratis untuk female.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('\n')
          .toLowerCase();
      expect(texts.contains('bonus'), isFalse);
      expect(texts.contains('top up first'), isFalse);
    });

    testWidgets('male ($lang): harga + bonus selamat datang, tanpa withdraw', (
      tester,
    ) async {
      await tester.pumpWidget(host(false));
      expect(find.text(s.pointsOnboardMaleWelcome), findsOneWidget);
      expect(find.text(s.pointsOnboardMaleCall(10, 20)), findsOneWidget);
      expect(find.text(s.pointsOnboardMaleMatch(10)), findsOneWidget);
      expect(find.text(s.pointsOnboardMaleGift(10, 1000)), findsOneWidget);
      expect(find.text(s.pointsOnboardFemaleWithdraw(1500)), findsNothing);
      expect(find.text(s.pointsOnboardFemaleSub), findsNothing);
    });
  }

  test('teks onboarding tidak lagi menjanjikan 50 YukCoin gratis', () {
    for (final isId in [true, false]) {
      final s = S(isId: isId);
      expect(s.pointsOnboardMaleWelcome.contains('50'), isFalse);
    }
  });
}
