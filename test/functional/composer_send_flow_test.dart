import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/widgets/chat_composer_input.dart';

/// Functional: composer → ketik → tombol kirim → `onSend` terpanggil 1×.
/// Hermetic (tanpa plugin/network). Mount `ChatComposerInput` nyata.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
        home: ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider(),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(height: 320, child: child),
            ),
          ),
        ),
      );

  ChatComposerInput build({
    required TextEditingController ctrl,
    required VoidCallback onSend,
    bool showAttachRow = false,
    VoidCallback? onToggleAttach,
    VoidCallback? onSendPhoto,
    VoidCallback? onTakePhoto,
    VoidCallback? onSendViewOnce,
    VoidCallback? onOpenGiftPanel,
    VoidCallback? onSendCoin,
  }) =>
      ChatComposerInput(
        controller: ctrl,
        onSend: onSend,
        showAttachRow: showAttachRow,
        onToggleAttach: onToggleAttach ?? () {},
        onTakePhoto: onTakePhoto ?? () {},
        onSendPhoto: onSendPhoto ?? () {},
        onSendViewOnce: onSendViewOnce ?? () {},
        onOpenGiftPanel: onOpenGiftPanel,
        onSendCoin: onSendCoin,
      );

  testWidgets('ketik teks → tap tombol kirim → onSend sekali', (tester) async {
    final ctrl = TextEditingController();
    var sent = 0;
    await tester.pumpWidget(wrap(build(ctrl: ctrl, onSend: () => sent++)));

    await tester.enterText(find.byType(TextField), 'halo dunia');
    await tester.pump();
    expect(find.text('halo dunia'), findsOneWidget);

    // Tombol kirim (bukan mic) muncul saat ada teks.
    final sendBtn = find.byIcon(Icons.send_rounded);
    expect(sendBtn, findsOneWidget);
    await tester.tap(sendBtn);
    await tester.pump();

    expect(sent, 1);
    ctrl.dispose();
  });

  testWidgets('teks kosong → tampil tombol mic, bukan kirim', (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(wrap(build(ctrl: ctrl, onSend: () {})));

    expect(find.byIcon(Icons.send_rounded), findsNothing);
    expect(find.text('halo'), findsNothing);
    ctrl.dispose();
  });

  testWidgets('tap + → onToggleAttach terpanggil', (tester) async {
    final ctrl = TextEditingController();
    var toggled = 0;
    await tester.pumpWidget(wrap(build(
      ctrl: ctrl,
      onSend: () {},
      onToggleAttach: () => toggled++,
    )));

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    expect(toggled, 1);
    ctrl.dispose();
  });

  testWidgets('chip attach: foto & view-once memanggil callback tepat',
      (tester) async {
    final ctrl = TextEditingController();
    var photo = 0, viewOnce = 0;
    await tester.pumpWidget(wrap(build(
      ctrl: ctrl,
      onSend: () {},
      showAttachRow: true,
      onSendPhoto: () => photo++,
      onSendViewOnce: () => viewOnce++,
    )));

    await tester.tap(find.byIcon(Icons.image_rounded));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.timer_rounded));
    await tester.pump();

    expect(photo, 1);
    expect(viewOnce, 1);
    ctrl.dispose();
  });

  testWidgets('chip koin/gift hanya tampil bila sistem koin aktif',
      (tester) async {
    final ctrl = TextEditingController();
    // Tanpa callback koin → chip tidak tampil.
    await tester.pumpWidget(wrap(build(
      ctrl: ctrl,
      onSend: () {},
      showAttachRow: true,
    )));
    expect(find.byIcon(Icons.monetization_on_rounded), findsNothing);
    expect(find.byIcon(Icons.card_giftcard), findsNothing);
    ctrl.dispose();
  });

  testWidgets('chip koin/gift tampil saat callback diberikan', (tester) async {
    final ctrl = TextEditingController();
    var coin = 0;
    await tester.pumpWidget(wrap(build(
      ctrl: ctrl,
      onSend: () {},
      showAttachRow: true,
      onSendCoin: () => coin++,
      onOpenGiftPanel: () {},
    )));

    expect(find.byIcon(Icons.monetization_on_rounded), findsOneWidget);
    await tester.tap(find.byIcon(Icons.monetization_on_rounded));
    await tester.pump();
    expect(coin, 1);
    ctrl.dispose();
  });
}
