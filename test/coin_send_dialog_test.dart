import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/screens/private_chat/widgets/coin_gift_dialogs.dart';

import 'test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final s = S(isId: true);

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    AppFonts.setLocal(AppFonts.systemKey);
  });

  tearDownAll(resetFontForTest);

  testWidgets('dialog koin: preset lalu kirim, controller tidak dipakai '
      'setelah dispose', (tester) async {
    int? result;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showSendCoinDialog(
                      context,
                      otherName: 'anto',
                      pointsEnabled: true,
                      paidBalance: 50,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text(s.sendCoinTitle), findsOneWidget);

    await tester.tap(find.text('10 🪙'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, s.btnSend));
    await tester.pumpAndSettle();

    expect(result, 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dialog koin tidak overflow di layar kecil saat keyboard muncul',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 1920);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showSendCoinDialog(
                      context,
                      otherName: 'anto',
                      pointsEnabled: true,
                      paidBalance: 50,
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      await tester.pumpAndSettle();

      expect(find.text(s.sendCoinTitle), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(TextButton, s.btnCancel));
      await tester.pumpAndSettle();
    },
  );
}
