import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/core/nav_gate.dart';
import 'package:chatyuk/widgets/call_no_coin_dialog.dart';

/// Dialog "koin habis" & "batas gratis" — panggilan dijeda sampai user
/// memilih: isi koin (buka sheet top-up + onContinue) atau akhiri (onEnd).
void main() {
  final sEn = S(isId: false);
  bool? result;

  tearDown(() {
    NavGate.topupSheet = null;
  });

  Future<void> pumpAndCall(WidgetTester t, {
    int perMinute = 20,
    VoidCallback? onEnd,
    Future<void> Function()? onContinue,
  }) async {
    result = null;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => FilledButton(
              onPressed: () async {
                result = await showCallNoCoinDialog(
                  ctx,
                  perMinute: perMinute,
                  onEnd: onEnd ?? () {},
                  onContinue: onContinue ?? () async {},
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('pilih Akhiri → onEnd dipanggil, return false', (t) async {
    var ended = 0;
    await pumpAndCall(t, onEnd: () => ended++);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(sEn.callNoCoinTitle), findsOneWidget);
    expect(find.text(sEn.callNoCoinBody(20)), findsOneWidget);

    await t.tap(find.text(sEn.callNoCoinEnd));
    await t.pumpAndSettle();

    expect(result, false);
    expect(ended, 1);
  });

  testWidgets('pilih Isi YukCoin → sheet topup + onContinue, return true',
      (t) async {
    var continued = 0;
    var sheetShown = 0;
    NavGate.topupSheet = (ctx, s) => sheetShown++;

    await pumpAndCall(t, onContinue: () async => continued++);

    await t.tap(find.text(sEn.callNoCoinTopup));
    await t.pumpAndSettle();

    expect(result, true);
    expect(continued, 1);
    expect(sheetShown, 1);
  });

  testWidgets('Isi YukCoin tanpa handler sheet → SnackBar + tetap lanjut',
      (t) async {
    var continued = 0;
    await pumpAndCall(t, onContinue: () async => continued++);

    await t.tap(find.text(sEn.callNoCoinTopup));
    await t.pumpAndSettle();

    expect(result, true);
    expect(continued, 1);
    expect(find.text(sEn.yukcoinTopupSoon), findsOneWidget);
  });

  testWidgets('barrier tidak bisa dismiss (paksa pilih)', (t) async {
    var ended = 0;
    await pumpAndCall(t, onEnd: () => ended++);

    // Tap di sudut layar — di luar dialog.
    await t.tapAt(const Offset(2, 2));
    await t.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(ended, 0);
  });

  testWidgets('free limit: satu tombol Akhiri → onEnd', (t) async {
    var ended = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => FilledButton(
              onPressed: () => showCallFreeLimitDialog(
                ctx,
                limitMin: 10,
                onEnd: () => ended++,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(find.text(sEn.callFreeLimitTitle), findsOneWidget);
    expect(find.text(sEn.callFreeLimitBody(10)), findsOneWidget);
    // Tidak ada tombol isi koin — female tidak pernah ditagih.
    expect(find.text(sEn.callNoCoinTopup), findsNothing);

    await t.tap(find.text(sEn.callNoCoinEnd));
    await t.pumpAndSettle();
    expect(ended, 1);
  });
}
