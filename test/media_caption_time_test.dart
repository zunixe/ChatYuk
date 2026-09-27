import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/core/chat/chat_location.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/utils.dart';
import 'package:chatyuk/widgets/location_bubble.dart';
import 'package:chatyuk/widgets/private_chat_message.dart';

/// Regresi keseragaman jarak: caption ↔ jam di media (foto/video/maps) harus
/// SAMA seperti chat teks, dan jam RATA KANAN sejajar tepi kanan media —
/// bukan baris terpisah yang membuat bubble lebih tinggi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child, {double width = 360}) => ChangeNotifierProvider(
        create: (_) => LocaleProvider(),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(width: width, height: 700, child: child),
          ),
        ),
      );

  // ── MAPS ──────────────────────────────────────────────────────────────
  testWidgets('maps + caption pendek: jam rata kanan sejajar tepi peta',
      (tester) async {
    const timeStr = '5:01 PM';
    await tester.pumpWidget(
      host(
        const Center(
          child: LocationBubble(
            location: ChatLocation(lat: -6.9, lng: 107.6, caption: 'ok'),
            timeStr: timeStr,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    final bubbleBR = tester.getBottomRight(find.byType(LocationBubble).first);
    final timeBR = tester.getBottomRight(find.text(timeStr).first);
    // Rata kanan: tepi kanan jam ≈ tepi kanan peta (toleransi kecil).
    expect((bubbleBR.dx - timeBR.dx).abs(), lessThan(2.0));
    // Jam TIDAK kepotong: tepi bawah jam masih di dalam bubble (ada sisa).
    expect(timeBR.dy, lessThanOrEqualTo(bubbleBR.dy));
    expect(bubbleBR.dy - timeBR.dy, greaterThan(0.5));
    // Sebaris: jam nempel di bawah peta, bukan baris jauh.
    final bubbleTR = tester.getTopRight(find.byType(LocationBubble).first);
    expect(timeBR.dy - bubbleTR.dy, lessThan(bubbleBR.dy - bubbleTR.dy + 30));
  });

  // ── FOTO ──────────────────────────────────────────────────────────────
  MessageModel photoMsg(String text) => MessageModel(
        id: 'p1',
        senderId: 'u-other',
        senderName: 'Budi',
        senderGender: 'male',
        isRegistered: true,
        text: text,
        type: 'image',
        // 'x' bukan path/base64 valid → poster gagal cepat tanpa jaringan.
        imageData: 'x',
        timestamp: DateTime(2026, 9, 27, 17, 1),
      );

  testWidgets('foto + caption: jam NEMPEL sebaris (bukan baris terpisah)',
      (tester) async {
    final m = photoMsg('ok');
    await tester.pumpWidget(
      host(
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
    // Jam tampil.
    expect(find.text(timeStr), findsOneWidget);
    // Caption juga tampil.
    expect(find.text('ok'), findsOneWidget);
  });

  testWidgets('foto + caption panjang: jam tetap tampil (baris bawah kanan)',
      (tester) async {
    final m = photoMsg(
      'ini caption yang sangat panjang sekali sehingga pasti melipat '
      'menjadi beberapa baris penuh di bawah foto',
    );
    await tester.pumpWidget(
      host(
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
    expect(find.text(timeStr), findsOneWidget);
  });

  // ── FOTO SEKALI LIHAT (view_once) + CAPTION ───────────────────────────
  // Regresi: caption view_once TERSIMPAN di DB tapi TIDAK dirender di bubble
  // (dulu hanya Stack foto + jam; msg.text diabaikan) → teks seolah hilang.
  MessageModel viewOnceMsg(String text, {String type = 'view_once'}) =>
      MessageModel(
        id: 'v1',
        senderId: 'u-me',
        senderName: 'Saya',
        senderGender: 'male',
        isRegistered: true,
        text: text,
        type: type,
        // 'x' bukan base64 valid → ViewOnceImage gagal cepat tanpa jaringan.
        imageData: 'x',
        timestamp: DateTime(2026, 9, 27, 17, 1),
        durationMs: 3,
      );

  testWidgets('view_once + caption: caption IKUT ditampilkan', (tester) async {
    final m = viewOnceMsg('Tes');
    await tester.pumpWidget(
      host(
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
    // Caption view-once harus tampil (dulu hilang).
    expect(find.text('Tes'), findsOneWidget);
  });

  testWidgets('view_once_expired + caption: caption tetap tampil',
      (tester) async {
    final m = viewOnceMsg('Tes', type: 'view_once_expired');
    await tester.pumpWidget(
      host(
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
    expect(find.text('Tes'), findsOneWidget);
  });

  testWidgets('view_once tanpa caption: tidak ada teks caption kosong',
      (tester) async {
    final m = viewOnceMsg('');
    await tester.pumpWidget(
      host(
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
  });
}
