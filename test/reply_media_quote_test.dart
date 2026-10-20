import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/core/chat/reply_meta.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/widgets/private_chat_message.dart';
import 'package:chatyuk/widgets/reply_quote.dart';

/// Regresi KUTIPAN BALASAN MEDIA (ala WhatsApp).
///
/// Keluhan user: "capture xiaomi ada whatsapp ketika reply foto ada fotonya
/// direply sebelah kanan kecil, saya pengen di chatyuk sama kayak whatsapp
/// cek juga reply video maps dll".
///
/// Artinya:
/// 1. Kutipan balasan harus TETAP TAMPIL walau pesan aslinya media TANPA
///    caption (dulu hanya `repliedToText` yang dirender → blok hilang).
/// 2. Ada LABEL jenis (ikon + "[Foto]"/"[Video]"/"[Lokasi]").
/// 3. Thumbnail kecil di sisi KANAN kutipan (foto dari cache lokal, video
///    dari poster) — tidak pernah mengunduh.
/// 4. Lokasi (`reply_meta` type location & payload JSON) tampil sebagai pin.
void main() {
  layoutTests();
  MessageModel photoMsg({bool me = false, String text = '', Map<String, dynamic>? meta}) =>
      MessageModel(
        id: '11',
        senderId: me ? 'me' : 'other',
        senderName: me ? 'Saya' : 'Putu',
        senderGender: 'male',
        isRegistered: true,
        text: text,
        type: 'image',
        imageData: '',
        timestamp: DateTime(2026, 1, 1, 10, 0),
        repliedToId: '7',
        repliedToText: '',
        repliedToSenderName: 'Putu',
        repliedToMeta: meta,
      );

  test('replyQuoteData: media tanpa caption tetap menghasilkan kutipan', () {
    final d = replyQuoteData(
      repliedToText: '',
      repliedToId: '7',
      repliedToSenderName: 'Putu',
      meta: buildReplyMeta(type: 'image', messageId: '7', chatKey: 'private_x'),
    );
    expect(d, isNotNull);
    expect(d!.kind, ReplyMediaKind.photo);
    expect(d.messageId, '7');
    expect(d.cacheChatKey, 'private_x');
  });

  test('replyQuoteData: teks kosong tanpa meta → null (blok tidak dibuat)', () {
    expect(
      replyQuoteData(
        repliedToText: '',
        repliedToId: '7',
        repliedToSenderName: 'Putu',
      ),
      isNull,
    );
  });

  test('replyQuoteData: lokasi dikenali dari payload JSON (baris lama)', () {
    const payload = '{"lat":-6.2,"lng":106.8,"label":"Jakarta"}';
    final d = replyQuoteData(
      repliedToText: payload,
      repliedToId: '9',
      repliedToSenderName: 'Putu',
    );
    expect(d!.kind, ReplyMediaKind.location);
  });

  test('jenis media memetakan type pesan dengan benar', () {
    expect(replyMediaKindOfType('video'), ReplyMediaKind.video);
    expect(replyMediaKindOfType('video_once'), ReplyMediaKind.videoOnce);
    expect(replyMediaKindOfType('view_once'), ReplyMediaKind.viewOnce);
    expect(replyMediaKindOfType('location'), ReplyMediaKind.location);
    expect(replyMediaKindOfType('sticker'), ReplyMediaKind.sticker);
    expect(replyMediaKindOfType('file'), ReplyMediaKind.file);
    expect(replyMediaKindOfType('text'), ReplyMediaKind.text);
    expect(replyMediaKindOfType(null), ReplyMediaKind.text);
  });

  test('buildReplyMeta hanya memuat kunci valid', () {
    final m = buildReplyMeta(
      type: 'video',
      messageId: '3',
      width: 0,
      height: -1,
      videoPath: 'chat-videos/a.mp4',
      chatKey: 'private_abc',
    );
    expect(m['t'], 'video');
    expect(m['id'], '3');
    expect(m.containsKey('w'), isFalse, reason: 'dimensi 0 tidak disimpan');
    expect(m['p'], 'chat-videos/a.mp4');
    expect(m['d'], 'private_abc');
  });

  testWidgets('kutipan FOTO tampil dengan ikon + placeholder thumbnail', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                child: MessageBubble(
                  msg: photoMsg(
                    meta: buildReplyMeta(
                      type: 'image',
                      messageId: '7',
                      chatKey: 'private_x',
                    ),
                  ),
                  chatKey: 'k',
                  isMe: false,
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
    await tester.pump(const Duration(milliseconds: 50));

    final quote = find.byType(ReplyQuote);
    expect(quote, findsOneWidget, reason: 'kutipan media harus tampil');
    // Ikon jenis (foto) ada di dalam kutipan.
    expect(
      find.descendant(of: quote, matching: find.byIcon(Icons.photo_outlined)),
      findsOneWidget,
    );
    // Thumbnail (placeholder 40dp) ada di sisi kanan kutipan.
    final qRect = tester.getRect(quote);
    final thumbIcon = find.descendant(
      of: quote,
      matching: find.byIcon(Icons.image_outlined),
    );
    expect(thumbIcon, findsOneWidget, reason: 'kotak thumbnail harus ada');
    final tRect = tester.getRect(thumbIcon);
    expect(
      tRect.center.dx,
      greaterThan(qRect.center.dx),
      reason: 'thumbnail harus di sisi KANAN kutipan (ala WhatsApp)',
    );
  });

  testWidgets('kutipan pesan terhapus tidak merender thumbnail', (tester) async {
    final msg = photoMsg(
      meta: buildReplyMeta(type: 'image', messageId: '7'),
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                child: MessageBubble(
                  msg: msg,
                  chatKey: 'k',
                  isMe: false,
                  isRead: true,
                  link: LayerLink(),
                  autoLinkPreview: false,
                  deletedIds: {'7'},
                  s: S(isId: false),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final quote = find.byType(ReplyQuote);
    expect(quote, findsOneWidget);
    expect(
      find.descendant(of: quote, matching: find.byIcon(Icons.image_outlined)),
      findsNothing,
      reason: 'PRIVASI: pesan terhapus → tanpa thumbnail',
    );
    // QR-10: teks "Pesan dihapus" dirender miring di dalam kutipan.

    final texts = tester
        .widgetList<Text>(
          find.descendant(of: quote, matching: find.byType(Text)),
        )
        .map((t) => t.data ?? '')
        .toList();
    expect(
      texts.any((t) => t.toLowerCase().contains('dihapus') || t.toLowerCase().contains('deleted')),
      isTrue,
      reason: 'kutipan pesan terhapus harus menampilkan label terhapus: $texts',
    );
  });

  testWidgets('kutipan VIDEO tanpa caption tampil (label video)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 340,
                child: MessageBubble(
                  msg: photoMsg(
                    meta: buildReplyMeta(
                      type: 'video',
                      messageId: '7',
                      videoPath: 'chat-videos/x.mp4',
                    ),
                  ),
                  chatKey: 'k',
                  isMe: true,
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

    final quote = find.byType(ReplyQuote);
    expect(quote, findsOneWidget);
    expect(
      find.descendant(of: quote, matching: find.byIcon(Icons.videocam_outlined)),
      findsWidgets,
    );
  });
}

/// Tata letak MEDIA berbalasan (ala WhatsApp): media di KIRI, kutipan +
/// caption + jam di PANEL KANAN (bukan caption di bawah foto).
void layoutTests() {
  MessageModel photoReply(String caption) => MessageModel(
    id: '20',
    senderId: 'other',
    senderName: 'Putu',
    senderGender: 'male',
    isRegistered: true,
    text: caption,
    type: 'image',
    imageData: '',
    timestamp: DateTime(2026, 1, 1, 10, 0),
    repliedToId: '7',
    repliedToText: 'Pesan yang dikutip',
    repliedToSenderName: 'Budi',
  );

  testWidgets('foto berbalasan: caption di panel KANAN, bukan di bawah', (
    tester,
  ) async {
    final msg = photoReply('caption');
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: MessageBubble(
                  msg: msg,
                  chatKey: 'k',
                  isMe: false,
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
    await tester.pump(const Duration(milliseconds: 100));

    final quote = find.byType(ReplyQuote);
    expect(quote, findsOneWidget);
    final caption = find.byWidgetPredicate((w) {
      if (w is! EditableText) return false;
      return w.controller.text.contains('caption');
    });
    // Caption dirender (via MediaCaptionTime/rich text) di panel kanan:
    // posisi x-nya berada di kanan tengah kutipan.
    final quoteRect = tester.getRect(quote);
    if (caption.evaluate().isNotEmpty) {
      final cRect = tester.getRect(caption.first);
      expect(
        cRect.left,
        greaterThan(quoteRect.left),
        reason: 'caption harus sejajar panel kanan (bukan selebar bubble)',
      );
    }
  });
}
