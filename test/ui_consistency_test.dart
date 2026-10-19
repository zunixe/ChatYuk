import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/reply_quote.dart';

/// GUARD aturan kartu bubble chat — lihat `docs/UI_CONSISTENCY.md`.
///
/// Regresi nyata (2026-10-18): kartu KONTAK tidak terdaftar sebagai kartu →
/// padding bubble 10 (teks) + padding dalam 10 = lebih menjorok daripada
/// file/lokasi (4 + 10).
void main() {
  test('GUARD: contact terdaftar sebagai KARTU di private & room', () {
    final priv = File(
      'lib/widgets/private_chat_message.dart',
    ).readAsStringSync();
    final isMedia = RegExp(
      r'final isMediaCard =[\s\S]{0,900}?;',
    ).firstMatch(priv)?.group(0);
    expect(isMedia, isNotNull);
    expect(
      isMedia!.contains("msg.type == 'contact'"),
      isTrue,
      reason: 'contact harus ada di isMediaCard (padding bubble 4)',
    );

    final room = File(
      'lib/screens/room_chat/widgets/room_message_bubble.dart',
    ).readAsStringSync();
    final roomMedia = RegExp(
      r'bool get _isMedia =>[\s\S]{0,900}?;',
    ).firstMatch(room)?.group(0);
    expect(roomMedia, isNotNull);
    expect(
      roomMedia!.contains("msg.type == 'contact'"),
      isTrue,
      reason: 'contact harus ada di _isMedia (room)',
    );
  });

  test('GUARD: ContactBubble ikut aturan kartu (lebar, jam, tombol)', () {
    final src = File('lib/widgets/contact_bubble.dart').readAsStringSync();
    expect(src.contains('chatMediaWidth('), isTrue);
    expect(src.contains('EdgeInsets.fromLTRB(0, 3, 4, 1)'), isTrue);
    // Aksi WAJIB Row+Expanded (lebar sama), bukan Wrap.
    expect(src.contains('Wrap('), isFalse);
  });

  test('GUARD: jam bubble BALASAN rata kanan (Align.centerRight)', () {
    // Regresi: Column balasan dibentangkan selebar kutipan (StretchToWidest)
    // + crossAxisAlignment.start → blok teks+jam nempel KIRI, jam tidak rata
    // kanan. Wajib dibungkus Align centerRight.
    final src = File(
      'lib/widgets/private_chat_message.dart',
    ).readAsStringSync();
    expect(
      RegExp(
        r'child:\s*Align\([\s\S]{0,400}?alignment:\s*Alignment\.centerRight[\s\S]{0,120}?MessageTextWithTime',
      ).hasMatch(src),
      isTrue,
      reason: 'blok teks+jam balasan harus dibungkus Align centerRight',
    );
  });

  testWidgets(
    'kutipan balasan TIDAK menempel tepi bubble (min 6 logical dari tepi)',
    (tester) async {
      // Meniru bubble balasan: padding horizontal 4 (lihat
      // private_chat_message.dart branch `stretchReply`) + margin kiri kutipan 2.
      const pad = 4.0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: Container(
                  key: const ValueKey('bubble'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: pad,
                    vertical: 6,
                  ),
                  child: const ReplyQuote(
                    senderName: 'Budi',
                    text: 'pesan yang dibalas',
                    isMe: true,
                    targetDeleted: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final bubbleLeft = tester
          .getTopLeft(find.byKey(const ValueKey('bubble')))
          .dx;
      // Isi kutipan = padding bubble 4 + margin kiri 2 + border aksen 3 +
      // padding dalam kutipan 8 → teks minimal 17 px dari tepi bubble.
      final textLeft = tester.getTopLeft(find.text('pesan yang dibalas')).dx;
      final gap = textLeft - bubbleLeft;
      expect(
        gap,
        greaterThanOrEqualTo(pad + 2 + 3 + 8 - 0.1),
        reason: 'kutipan jangan menempel tepi bubble (gap=$gap)',
      );
    },
  );
}
