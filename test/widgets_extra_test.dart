import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/widgets/reply_quote.dart';
import 'package:chatyuk/widgets/room_icon.dart';
import 'package:chatyuk/widgets/story_text_overlay.dart';

void main() {
  final s = S(isId: true);

  Widget wrap(Widget child) => MaterialApp(
        home: ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider(),
          child: Scaffold(body: child),
        ),
      );

  group('RoomIcon', () {
    testWidgets('kategori dikenal → Material icon, bukan emoji',
        (tester) async {
      await tester.pumpWidget(
        wrap(const RoomIcon(category: 'general', emoji: '💬')),
      );
      expect(find.byIcon(Icons.chat_bubble_rounded), findsOneWidget);
      expect(find.text('💬'), findsNothing);
    });

    testWidgets('kategori tak dikenal → fallback emoji custom',
        (tester) async {
      await tester.pumpWidget(
        wrap(const RoomIcon(category: 'custom-xyz', emoji: '🎮')),
      );
      expect(find.text('🎮'), findsOneWidget);
    });

    testWidgets('kategori kosong → fallback emoji', (tester) async {
      await tester.pumpWidget(
        wrap(const RoomIcon(category: '', emoji: '🔥')),
      );
      expect(find.text('🔥'), findsOneWidget);
    });
  });

  group('ReplyQuote', () {
    testWidgets('fromMessage null bila teks balasan kosong', (tester) async {
      late ReplyQuote? quote;
      await tester.pumpWidget(wrap(Builder(builder: (context) {
        quote = ReplyQuote.fromMessage(
          context: context,
          repliedToText: '',
          repliedToId: 'm1',
          repliedToSenderName: 'Budi',
          isMe: false,
          deletedIds: const {},
        );
        return const SizedBox();
      })));
      expect(quote, isNull);
    });

    testWidgets('fromMessage menandai targetDeleted bila id ada di set',
        (tester) async {
      late ReplyQuote? quote;
      await tester.pumpWidget(wrap(Builder(builder: (context) {
        quote = ReplyQuote.fromMessage(
          context: context,
          repliedToText: 'halo',
          repliedToId: 'm1',
          repliedToSenderName: 'Budi',
          isMe: false,
          deletedIds: const {'m1'},
        );
        return const SizedBox();
      })));
      expect(quote, isNotNull);
      expect(quote!.targetDeleted, isTrue);
      expect(quote!.text, 'halo');
    });

    testWidgets('pesan terhapus → tampil "Pesan dihapus" miring',
        (tester) async {
      await tester.pumpWidget(wrap(const ReplyQuote(
        senderName: 'Budi',
        text: 'rahasia',
        isMe: false,
        targetDeleted: true,
      )));
      expect(find.text(s.messageDeleted), findsOneWidget);
      expect(find.text('rahasia'), findsNothing);
    });

    testWidgets('normal → tampil teks asli', (tester) async {
      await tester.pumpWidget(wrap(const ReplyQuote(
        senderName: 'Budi',
        text: 'halo dunia',
        isMe: true,
        targetDeleted: false,
      )));
      expect(find.text('halo dunia'), findsOneWidget);
      expect(find.text('Budi'), findsOneWidget);
    });
  });

  group('StoryTextOverlay', () {
    testWidgets('teks kosong → SizedBox.shrink', (tester) async {
      await tester.pumpWidget(wrap(const StoryTextOverlay(
        text: '',
        x: 0.5,
        y: 0.5,
      )));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('teks tampil + withBg menambah container', (tester) async {
      await tester.pumpWidget(wrap(const StoryTextOverlay(
        text: 'Halo story',
        x: 0.5,
        y: 0.5,
        withBg: true,
        colorIndex: 2,
        sizeIndex: 2,
      )));
      expect(find.text('Halo story'), findsOneWidget);
    });

    testWidgets('colorIndex di luar jangkauan → fallback palette pertama',
        (tester) async {
      await tester.pumpWidget(wrap(const StoryTextOverlay(
        text: 'X',
        x: 0.5,
        y: 0.5,
        colorIndex: 999,
      )));
      final t = tester.widget<Text>(find.text('X'));
      expect(t.style!.color, StoryText.palette.first);
    });

    testWidgets('x/y di-clamp (tidak error saat di luar 0-1)', (tester) async {
      await tester.pumpWidget(wrap(const StoryTextOverlay(
        text: 'Clamp',
        x: 5.0,
        y: -3.0,
      )));
      expect(find.text('Clamp'), findsOneWidget);
      final align = tester.widget<Align>(find.byType(Align).last);
      final a = align.alignment as Alignment;
      expect(a.x, 1.0);
      expect(a.y, -1.0);
    });

    testWidgets('scale di-clamp antara 0.5 dan 3', (tester) async {
      await tester.pumpWidget(wrap(const StoryTextOverlay(
        text: 'S',
        x: 0.5,
        y: 0.5,
        sizeIndex: 1,
        scale: 999,
      )));
      final t = tester.widget<Text>(find.text('S'));
      expect(t.style!.fontSize, StoryText.size(1) * 3.0);
    });
  });
}
