import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/utils/mention.dart';
import 'package:chatyuk/widgets/chat_composer_input.dart';

/// Functional: alur mention lewat COMPOSER NYATA —
/// ketik `@` → panel kandidat muncul → pilih → teks jadi `@Nama ` → kirim.
/// Hermetic, tanpa plugin/network.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const budi = Mention(uid: 'u-budi', name: 'Budi');

  Widget wrap(Widget child) => MaterialApp(
        home: ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider(),
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(height: 400, child: child),
            ),
          ),
        ),
      );

  testWidgets('ketik @ → panel kandidat muncul → pilih → teks @Budi + spasi',
      (tester) async {
    final ctrl = TextEditingController();
    var sent = 0;
    await tester.pumpWidget(wrap(ChatComposerInput(
      controller: ctrl,
      onSend: () => sent++,
      showAttachRow: false,
      onToggleAttach: () {},
      onTakePhoto: () {},
      onSendPhoto: () {},
      onSendViewOnce: () {},
      mentionCandidates: const [budi],
    )));

    await tester.enterText(find.byType(TextField), 'halo @bud');
    await tester.pump();
    expect(find.text('Budi'), findsOneWidget);

    await tester.tap(find.text('Budi'));
    await tester.pump();

    expect(ctrl.text, 'halo @Budi ');
    expect(ctrl.selection.baseOffset, 'halo @Budi '.length);

    // Kirim → teks membawa mention utuh.
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(sent, 1);
    ctrl.dispose();
  });

  testWidgets('spasi setelah @ → panel tertutup', (tester) async {
    final ctrl = TextEditingController();
    await tester.pumpWidget(wrap(ChatComposerInput(
      controller: ctrl,
      onSend: () {},
      showAttachRow: false,
      onToggleAttach: () {},
      onTakePhoto: () {},
      onSendPhoto: () {},
      onSendViewOnce: () {},
      mentionCandidates: const [budi],
    )));

    await tester.enterText(find.byType(TextField), 'halo @bud');
    await tester.pump();
    expect(find.text('Budi'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'halo @bud ');
    await tester.pump();
    expect(find.text('Budi'), findsNothing);
    ctrl.dispose();
  });
}
