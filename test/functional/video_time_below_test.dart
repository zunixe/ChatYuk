import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/utils.dart';
import 'package:chatyuk/widgets/chat_video_bubble.dart';
import 'package:chatyuk/widgets/private_chat_message.dart';

/// Regresi: kartu video penerima TIDAK boleh lebih lebar dari video (200).
/// Jam harus di bawah video, tepi kanan sejajar tepi video — sama seperti
/// bubble maps (LocationBubble 220). Data 'x' bukan path & bukan base64
/// valid → poster gagal cepat tanpa jaringan/plugin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MessageModel videoMsg() => MessageModel(
        id: 'v1',
        senderId: 'u-other',
        senderName: 'Budi',
        senderGender: 'male',
        isRegistered: true,
        text: '',
        type: 'video',
        imageData: 'x',
        durationMs: 2000,
        timestamp: DateTime(2026, 9, 27, 17, 1),
      );

  Widget wrap(Widget child) => MaterialApp(
        home: ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider(),
          child: Scaffold(
            body: SizedBox(width: 360, height: 600, child: child),
          ),
        ),
      );

  testWidgets('kartu video rapat (200+padding), jam di bawah sejajar kanan',
      (tester) async {
    final m = videoMsg();
    await tester.pumpWidget(
      wrap(
        MessageBubble(
          msg: m,
          chatKey: 'chat_1',
          isMe: false,
          isRead: false,
          link: LayerLink(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    final timeStr = formatBubbleTime(m.timestamp);
    // Tepi kanan BARIS jam, bukan teks saja (ada varian + centang).
    final timeRow = find.ancestor(
      of: find.text(timeStr),
      matching: find.byType(Row),
    ).first;
    final videoBR =
        tester.getBottomRight(find.byType(ChatVideoBubble).first);
    final timeTR = tester.getTopRight(timeRow);
    final timeBR = tester.getBottomRight(timeRow);

    // Jam di BAWAH video (bukan overlay menumpuk durasi).
    expect(timeTR.dy, greaterThanOrEqualTo(videoBR.dy));
    // Jam rata kanan sejajar tepi kanan video (flush, tanpa jeda).
    expect((videoBR.dx - timeBR.dx).abs(), lessThan(1.5));
  });

  testWidgets('video kadaluarsa: jam DI DALAM card (ikut foto kadaluarsa)',
      (tester) async {
    final m = MessageModel(
      id: 'v2',
      senderId: 'u-other',
      senderName: 'Budi',
      senderGender: 'male',
      isRegistered: true,
      text: '',
      type: 'video_once_expired',
      imageData: 'x',
      timestamp: DateTime(2026, 9, 27, 17, 1),
    );
    await tester.pumpWidget(
      wrap(
        MessageBubble(
          msg: m,
          chatKey: 'chat_1',
          isMe: false,
          isRead: false,
          link: LayerLink(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    final timeStr = formatBubbleTime(m.timestamp);
    final cardTR =
        tester.getTopRight(find.byType(ViewOnceLockedCard).first);
    final cardBR =
        tester.getBottomRight(find.byType(ViewOnceLockedCard).first);
    final timeTR = tester.getTopRight(find.text(timeStr).first);
    final timeBR = tester.getBottomRight(find.text(timeStr).first);

    // Jam di dalam card: di bawah tepi atas & tidak lewat tepi bawah.
    expect(timeTR.dy, greaterThan(cardTR.dy));
    expect(timeBR.dy, lessThanOrEqualTo(cardBR.dy + 1.0));
    // Rata kanan dalam card.
    expect(cardBR.dx - timeBR.dx, lessThan(20.0));
  });

  testWidgets('video kadaluarsa PENGIRIM (masih putar): jam di bawah',
      (tester) async {
    final m = MessageModel(
      id: 'v3',
      senderId: 'u-me',
      senderName: 'Saya',
      senderGender: 'male',
      isRegistered: true,
      text: '',
      type: 'video_once_expired',
      imageData: 'x',
      durationMs: 2000,
      timestamp: DateTime(2026, 9, 27, 14, 41),
    );
    await tester.pumpWidget(
      wrap(
        MessageBubble(
          msg: m,
          chatKey: 'chat_1',
          isMe: true,
          isRead: true,
          link: LayerLink(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    final timeStr = formatBubbleTime(m.timestamp);
    // Tepi kanan BARIS jam (teks + centang), bukan teks saja.
    final timeRow = find.ancestor(
      of: find.text(timeStr),
      matching: find.byType(Row),
    ).first;
    final videoBR =
        tester.getBottomRight(find.byType(ChatVideoBubble).first);
    final timeTR = tester.getTopRight(timeRow);
    final timeBR = tester.getBottomRight(timeRow);

    // Durasi tetap di dalam, jam + centang di bawah rata kanan tepi video.
    expect(timeTR.dy, greaterThanOrEqualTo(videoBR.dy));
    expect((videoBR.dx - timeBR.dx).abs(), lessThan(1.5));
  });

  testWidgets('video caption pendek: jam NEMPEL sebaris ala chat teks',
      (tester) async {
    final m = MessageModel(
      id: 'v4',
      senderId: 'u-other',
      senderName: 'Budi',
      senderGender: 'male',
      isRegistered: true,
      text: 'ok',
      type: 'video',
      imageData: 'x',
      durationMs: 2000,
      timestamp: DateTime(2026, 9, 27, 17, 1),
    );
    await tester.pumpWidget(
      wrap(
        MessageBubble(
          msg: m,
          chatKey: 'chat_1',
          isMe: false,
          isRead: false,
          link: LayerLink(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    final timeStr = formatBubbleTime(m.timestamp);
    final videoBR =
        tester.getBottomRight(find.byType(ChatVideoBubble).first);
    final timeRow = find.ancestor(
      of: find.text(timeStr),
      matching: find.byType(Row),
    ).first;
    final timeTR = tester.getTopRight(timeRow);
    final timeBR = tester.getBottomRight(timeRow);

    // Sebaris caption: jam rapat (bukan baris jauh) & mentok kanan video.
    expect(timeTR.dy - videoBR.dy, lessThan(25.0));
    expect((videoBR.dx - timeBR.dx).abs(), lessThan(2.0));
  });

  testWidgets('video caption panjang: jam di bawah kanan', (tester) async {
    final m = MessageModel(
      id: 'v5',
      senderId: 'u-other',
      senderName: 'Budi',
      senderGender: 'male',
      isRegistered: true,
      text: 'ini caption yang sangat panjang sehingga melipat '
          'jadi beberapa baris penuh di dalam bubble video',
      type: 'video',
      imageData: 'x',
      durationMs: 2000,
      timestamp: DateTime(2026, 9, 27, 17, 1),
    );
    await tester.pumpWidget(
      wrap(
        MessageBubble(
          msg: m,
          chatKey: 'chat_1',
          isMe: false,
          isRead: false,
          link: LayerLink(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);

    final timeStr = formatBubbleTime(m.timestamp);
    final videoBR =
        tester.getBottomRight(find.byType(ChatVideoBubble).first);
    final timeRow = find.ancestor(
      of: find.text(timeStr),
      matching: find.byType(Row),
    ).first;
    final timeTR = tester.getTopRight(timeRow);
    final timeBR = tester.getBottomRight(timeRow);

    // Di bawah caption, rata kanan selebar video.
    expect(timeTR.dy, greaterThan(videoBR.dy + 30.0));
    expect(timeBR.dx - videoBR.dx, lessThan(2.0));
  });
}
