import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/utils/mention.dart';
import 'package:chatyuk/widgets/mention_autocomplete.dart';
import 'package:chatyuk/widgets/mention_spans.dart';

void main() {
  const budi = Mention(uid: 'u-budi', name: 'Budi');
  const budiSantoso = Mention(uid: 'u-bs', name: 'Budi Santoso');

  TextStyle styleOf(TextSpan s) => s.style ?? const TextStyle();

  bool isMention(TextSpan s) =>
      styleOf(s).color == AppTheme.primary &&
      styleOf(s).fontWeight == FontWeight.w600;

  String textOf(List<TextSpan> spans) =>
      spans.map((s) => s.text ?? '').join();

  group('mentionAwareSpans', () {
    test('teks kosong → satu span base', () {
      final spans = mentionAwareSpans('', const TextStyle());
      expect(spans.length, 1);
      expect(spans.single.text, '');
    });

    test('tanpa match → satu span base tanpa highlight', () {
      final spans = mentionAwareSpans('halo dunia', const TextStyle());
      expect(spans.length, 1);
      expect(spans.single.text, 'halo dunia');
      expect(isMention(spans.single), isFalse);
    });

    test('mention bernama disorot, teks lain utuh', () {
      final spans = mentionAwareSpans(
        'halo @Budi apa kabar',
        const TextStyle(),
        mentions: const [budi],
      );
      expect(textOf(spans), 'halo @Budi apa kabar');
      final marked = spans.where((s) => s.text == '@Budi');
      expect(marked.length, 1);
      expect(isMention(marked.single), isTrue);
    });

    test('nama lebih panjang menang (Budi Santoso > Budi)', () {
      final spans = mentionAwareSpans(
        'cc @Budi Santoso',
        const TextStyle(),
        mentions: const [budi, budiSantoso],
      );
      final marked = spans.where(isMention).toList();
      expect(marked.length, 1);
      expect(marked.single.text, '@Budi Santoso');
    });

    test('@all TIDAK disorot saat highlightAll=false (global room)', () {
      final spans = mentionAwareSpans(
        '@all kumpul',
        const TextStyle(),
        highlightAll: false,
      );
      expect(spans.where(isMention), isEmpty);
    });

    test('@all DISOROT saat highlightAll=true (grup owner/admin)', () {
      final spans = mentionAwareSpans(
        '@all kumpul',
        const TextStyle(),
        highlightAll: true,
      );
      final marked = spans.where((s) => s.text == '@all');
      expect(marked.length, 1);
      expect(isMention(marked.single), isTrue);
    });

    test('@everyone disorot saat highlightAll=true', () {
      final spans = mentionAwareSpans(
        '@everyone hi',
        const TextStyle(),
        highlightAll: true,
      );
      expect(spans.any((s) => s.text == '@everyone' && isMention(s)), isTrue);
    });

    test('boundary: email tidak disorot', () {
      final spans = mentionAwareSpans(
        'email@Budi.com',
        const TextStyle(),
        mentions: const [budi],
      );
      expect(spans.where(isMention), isEmpty);
    });

    test('URL tetap jadi link, tidak tumpang tindih dengan mention', () {
      final spans = mentionAwareSpans(
        '@Budi lihat https://contoh.com/x',
        const TextStyle(),
        mentions: const [budi],
      );
      expect(spans.where(isMention).length, 1);
      final links = spans.where((s) => s.recognizer != null).toList();
      expect(links.length, 1);
      expect(links.single.text, 'https://contoh.com/x');
      expect(textOf(spans), '@Budi lihat https://contoh.com/x');
    });

    test('mention berulang: hanya kemunculan pertama disorot', () {
      final spans = mentionAwareSpans(
        '@Budi dan @Budi',
        const TextStyle(),
        mentions: const [budi],
      );
      expect(spans.where(isMention).length, 1);
    });
  });

  group('MentionAwareText', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('tanpa match → Text polos', (tester) async {
      await tester.pumpWidget(
        wrap(const MentionAwareText('halo dunia')),
      );
      expect(find.byType(Text), findsOneWidget);
      expect(find.byType(RichText), findsWidgets);
    });

    testWidgets('dengan mention → RichText dengan span', (tester) async {
      await tester.pumpWidget(
        wrap(const MentionAwareText('hai @Budi', mentions: [budi])),
      );
      expect(find.byType(RichText), findsWidgets);
      final rt = tester.widget<RichText>(
        find.byType(RichText).last,
      );
      expect(rt.text.toPlainText(), 'hai @Budi');
    });
  });

  group('MentionAutocomplete', () {
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

    testWidgets('panel muncul saat mengetik @ + kandidat tampil',
        (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(wrap(
        MentionAutocomplete(
          controller: ctrl,
          candidates: const [budi, budiSantoso],
        ),
      ));
      ctrl.value = const TextEditingValue(
        text: 'halo @bud',
        selection: TextSelection.collapsed(offset: 9),
      );
      await tester.pump();
      expect(find.text('Budi'), findsOneWidget);
      expect(find.text('Budi Santoso'), findsOneWidget);
    });

    testWidgets('tap kandidat menyisipkan @Nama + spasi & pindah kursor',
        (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(wrap(
        MentionAutocomplete(controller: ctrl, candidates: const [budi]),
      ));
      ctrl.value = const TextEditingValue(
        text: 'halo @bud',
        selection: TextSelection.collapsed(offset: 9),
      );
      await tester.pump();
      await tester.tap(find.text('Budi'));
      await tester.pump();
      expect(ctrl.text, 'halo @Budi ');
      expect(ctrl.selection.baseOffset, 'halo @Budi '.length);
    });

    testWidgets('@all TIDAK tampil saat allowAll=false', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(wrap(
        MentionAutocomplete(controller: ctrl, candidates: const [budi]),
      ));
      ctrl.value = const TextEditingValue(
        text: '@',
        selection: TextSelection.collapsed(offset: 1),
      );
      await tester.pump();
      expect(find.text('@all'), findsNothing);
      expect(find.text('Budi'), findsOneWidget);
    });

    testWidgets('@all tampil saat allowAll=true', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(wrap(
        MentionAutocomplete(
          controller: ctrl,
          candidates: const [budi],
          allowAll: true,
        ),
      ));
      ctrl.value = const TextEditingValue(
        text: '@',
        selection: TextSelection.collapsed(offset: 1),
      );
      await tester.pump();
      expect(find.text('@all'), findsOneWidget);
    });

    testWidgets('query tanpa kandidat → panel tersembunyi', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(wrap(
        MentionAutocomplete(controller: ctrl, candidates: const [budi]),
      ));
      ctrl.value = const TextEditingValue(
        text: 'halo @zzz',
        selection: TextSelection.collapsed(offset: 9),
      );
      await tester.pump();
      expect(find.text('Budi'), findsNothing);
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('spasi setelah @ menutup panel', (tester) async {
      final ctrl = TextEditingController();
      await tester.pumpWidget(wrap(
        MentionAutocomplete(controller: ctrl, candidates: const [budi]),
      ));
      ctrl.value = const TextEditingValue(
        text: 'halo @bud',
        selection: TextSelection.collapsed(offset: 9),
      );
      await tester.pump();
      expect(find.text('Budi'), findsOneWidget);
      ctrl.value = const TextEditingValue(
        text: 'halo @bud ',
        selection: TextSelection.collapsed(offset: 10),
      );
      await tester.pump();
      expect(find.text('Budi'), findsNothing);
    });
  });
}
