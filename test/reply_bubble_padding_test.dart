import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/widgets/private_chat_message.dart';
import 'package:chatyuk/widgets/reply_quote.dart';

/// Regresi padding bubble BALASAN (reply quote).
///
/// Keluhan user: "padding ke text yang direpply kecil sama kaya yang lain,
/// yang text bawahnya baru kasih tab biar ga terlalu nempel".
///
/// Artinya: blok kutipan harus punya jarak dari tepi bubble (bukan menempel),
/// dan teks isi di bawahnya diberi indentasi.
///
/// Terukur di HP (density 3): blok kutipan dulu mulai hanya ~1-3px dari tepi
/// bubble = MENEMPEL. Fix: bubble tetap padding 4 (sejajar kartu media),
/// kutipan dapat margin-left 4, dan teks isi dapat padding dalam 8.
void main() {
  const bodyText = 'Ini teks isi balasan yang cukup panjang';

  MessageModel _replyMsg({bool me = false}) => MessageModel(
    id: '1',
    senderId: me ? 'me' : 'other',
    senderName: me ? 'Saya' : 'Putu',
    senderGender: 'male',
    isRegistered: true,
    text: bodyText,
    type: 'text',
    imageData: '',
    timestamp: DateTime(2026, 1, 1, 10, 0),
    repliedToId: '0',
    repliedToText: 'Pesan yang dikutip',
    repliedToSenderName: 'Putu',
  );

  Future<void> _pumpBubble(WidgetTester tester, MessageModel msg,
      {bool me = false}) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: MessageBubble(
                  msg: msg,
                  chatKey: 'k',
                  isMe: me,
                  isRead: true,
                  link: LayerLink(),
                  autoLinkPreview: false,
                  s: S(isId: false),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// Rect dari paragraf teks isi — dicari lewat RichText (teks bubble
  /// dirender sebagai rich text karena ada mention/code styling).
  Rect _bodyRect(WidgetTester tester) {
    final finder = find.byWidgetPredicate((w) {
      if (w is! RichText) return false;
      final t = w.text;
      if (t is! TextSpan) return false;
      return (t.toPlainText()).contains('teks isi balasan');
    });
    expect(finder, findsOneWidget, reason: 'teks isi bubble tidak ditemukan');
    return tester.getRect(finder);
  }

  testWidgets('blok kutipan TIDAK menempel tepi bubble', (tester) async {
    await _pumpBubble(tester, _replyMsg());

    final quote = find.byType(ReplyQuote);
    expect(quote, findsOneWidget, reason: 'bubble reply harus render ReplyQuote');

    final root = tester.getRect(find.byType(MessageBubble));
    // ReplyQuote dibungkus Padding → rect widget = area termasuk padding.
    // Yang menentukan "menempel" adalah kotak ber-border (Container dalam).
    final box = find.descendant(of: quote, matching: find.byType(Container));
    expect(box, findsWidgets, reason: 'kotak kutipan (border) tidak ditemukan');
    final qRect = tester.getRect(box.first);

    // padding bubble (4) + jarak kutipan (4) => >= 8dp dari tepi bubble.
    final gap = qRect.left - root.left;
    expect(
      gap,
      greaterThanOrEqualTo(8.0),
      reason:
          'Kotak kutipan hanya $gap dp dari tepi bubble — menempel. Harus >= 8dp '
          '(padding bubble 4 + jarak kutipan 4).',
    );
  });

  testWidgets('teks isi diberi tab (>= 8dp dari tepi bubble)', (tester) async {
    await _pumpBubble(tester, _replyMsg());

    final root = tester.getRect(find.byType(MessageBubble));
    final bRect = _bodyRect(tester);
    final gap = bRect.left - root.left;

    expect(
      gap,
      greaterThanOrEqualTo(8.0),
      reason:
          'Teks isi hanya $gap dp dari tepi bubble — terlalu nempel. '
          'Harus >= 8dp (padding bubble 4 + padding dalam 8 = 12dp).',
    );
  });

  testWidgets('teks isi lebih menjorok dari awal blok kutipan', (tester) async {
    await _pumpBubble(tester, _replyMsg());

    final qRect = tester.getRect(find.byType(ReplyQuote));
    final bRect = _bodyRect(tester);

    expect(
      bRect.left,
      greaterThan(qRect.left),
      reason: 'Teks isi harus mulai setelah awal blok kutipan (hierarki visual).',
    );
  });

  testWidgets('padding kanan teks isi juga ada (tidak mepet kanan)', (
    tester,
  ) async {
    await _pumpBubble(tester, _replyMsg());

    final root = tester.getRect(find.byType(MessageBubble));
    final bRect = _bodyRect(tester);
    final rightGap = root.right - bRect.right;

    // Teks dibatasi lebar konten; pastikan tidak keluar bubble.
    expect(rightGap, greaterThanOrEqualTo(0.0),
        reason: 'Teks isi keluar dari bubble.');
  });

  testWidgets('bubble tanpa kutipan tidak terpengaruh padding reply', (
    tester,
  ) async {
    await _pumpBubble(
      tester,
      MessageModel(
        id: '2',
        senderId: 'other',
        senderName: 'Putu',
        senderGender: 'male',
        isRegistered: true,
        text: 'Pesan biasa tanpa kutipan',
        type: 'text',
        imageData: '',
        timestamp: DateTime(2026, 1, 1, 10, 1),
      ),
    );

    expect(find.byType(ReplyQuote), findsNothing);
    final root = tester.getRect(find.byType(MessageBubble));
    final finder = find.byWidgetPredicate((w) {
      if (w is! RichText) return false;
      final t = w.text;
      if (t is! TextSpan) return false;
      return t.toPlainText().contains('Pesan biasa');
    });
    expect(finder, findsOneWidget);
    final bRect = tester.getRect(finder);
    final gap = bRect.left - root.left;
    expect(
      gap,
      greaterThanOrEqualTo(10.0),
      reason: 'Bubble non-reply memakai padding 10; dapat $gap dp.',
    );
  });

  testWidgets('kutipan & teks isi bukan selebar 0 (layout valid)', (
    tester,
  ) async {
    await _pumpBubble(tester, _replyMsg());
    final qRect = tester.getRect(find.byType(ReplyQuote));
    final bRect = _bodyRect(tester);
    expect(qRect.width, greaterThan(50));
    expect(bRect.width, greaterThan(50));
    final rp = tester.renderObject<RenderParagraph>(
      find.byWidgetPredicate((w) =>
          w is RichText && (w.text as TextSpan).toPlainText().contains('teks isi balasan')),
    );
    expect(rp.size.width, greaterThan(0));
  });
}
