import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/gifts.dart';
import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/widgets/chat_composer_input.dart';

/// Kunci: user perempuan tidak bisa kirim gift di private chat → ikon gift
/// (tombol composer & item menu lampiran) hilang; laki-laki tetap ada.
/// Gender belum diketahui → tetap tampil (perilaku lama).
void main() {
  group('canSendCoinsForGender', () {
    test('female → tidak boleh, male → boleh', () {
      expect(canSendCoinsForGender('female'), isFalse);
      expect(canSendCoinsForGender('male'), isTrue);
      expect(canSendCoinsForGender(null), isTrue);
    });
  });

  group('canSendGiftForGender', () {
    test('female → tidak boleh', () {
      expect(canSendGiftForGender('female'), isFalse);
    });
    test('male → boleh', () {
      expect(canSendGiftForGender('male'), isTrue);
    });
    test('tak diketahui → boleh (aman, perilaku lama)', () {
      expect(canSendGiftForGender(null), isTrue);
      expect(canSendGiftForGender(''), isTrue);
      expect(canSendGiftForGender('other'), isTrue);
    });
  });

  // Meniru wiring private chat: onOpenGiftPanel hanya diisi bila
  // poin aktif DAN gender boleh kirim gift.
  Widget host(String? gender, {required bool attachOpen}) => ProviderScope(
    child: MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: ChatComposerInput(
          controller: TextEditingController(),
          onSend: () {},
          showAttachRow: attachOpen,
          onToggleAttach: () {},
          onTakePhoto: () {},
          onSendPhoto: () {},
          onSendViewOnce: () {},
          onOpenGiftPanel: canSendGiftForGender(gender) ? () {} : null,
          onSendCoin: canSendCoinsForGender(gender) ? () {} : null,
        ),
      ),
    ),
  );

  Finder giftIcons() => find.byWidgetPredicate(
    (w) =>
        w is Icon &&
        (w.icon == Icons.card_giftcard_outlined ||
            w.icon == Icons.card_giftcard_rounded),
  );

  testWidgets('perempuan → menu kirim koin tidak ada', (tester) async {
    await tester.pumpWidget(host('female', attachOpen: true));
    await tester.pump();
    expect(find.byIcon(Icons.monetization_on_rounded), findsNothing);
  });

  testWidgets('laki-laki → menu kirim koin ada', (tester) async {
    await tester.pumpWidget(host('male', attachOpen: true));
    await tester.pump();
    expect(find.byIcon(Icons.monetization_on_rounded), findsOneWidget);
  });

  for (final attachOpen in [false, true]) {
    final label = attachOpen ? 'menu lampiran terbuka' : 'composer';
    testWidgets('perempuan → ikon gift tidak ada ($label)', (tester) async {
      await tester.pumpWidget(host('female', attachOpen: attachOpen));
      await tester.pump();
      expect(giftIcons(), findsNothing);
    });

    testWidgets('laki-laki → ikon gift ada ($label)', (tester) async {
      await tester.pumpWidget(host('male', attachOpen: attachOpen));
      await tester.pump();
      expect(giftIcons(), findsWidgets);
    });
  }
}
