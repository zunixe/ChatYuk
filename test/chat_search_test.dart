import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/screens/private_chat_screen.dart';
import 'package:chatyuk/widgets/private_chat_message.dart';

/// Search dalam percakapan private chat (ala WhatsApp).
MessageModel _msg(String id, String text, {bool deleted = false}) =>
    MessageModel(
      id: id,
      senderId: 'u1',
      senderName: 'A',
      senderGender: 'male',
      isRegistered: true,
      text: text,
      type: 'text',
      imageData: '',
      timestamp: DateTime.utc(2026, 9, 25),
      isDeleted: deleted,
    );

void main() {
  group('searchChatMatches', () {
    final msgs = [
      _msg('m1', 'Halo apa kabar'),
      _msg('m2', 'Lagi makan nasi'),
      _msg('m3', 'HALO juga dong'),
      _msg('m4', '', deleted: false),
      _msg('m5', 'halo halo halo', deleted: true),
    ];

    test('cocok case-insensitive, urut terbaru dulu', () {
      expect(searchChatMatches(msgs, 'halo'), ['m3', 'm1']);
    });

    test('query kosong/spasi → kosong', () {
      expect(searchChatMatches(msgs, ''), isEmpty);
      expect(searchChatMatches(msgs, '   '), isEmpty);
    });

    test('tidak cocok → kosong', () {
      expect(searchChatMatches(msgs, 'xyz'), isEmpty);
    });

    test('pesan terhapus & teks kosong dilewati', () {
      expect(searchChatMatches(msgs, 'halo'), isNot(contains('m5')));
    });

    test('trim query', () {
      expect(searchChatMatches(msgs, '  makan '), ['m2']);
    });
  });

  group('applySearchHighlight', () {
    const base = TextStyle(color: Colors.white);

    test('query kosong → spans sama', () {
      const spans = [TextSpan(text: 'halo dunia')];
      expect(applySearchHighlight(spans, ''), same(spans));
    });

    test('bagian cocok diberi background', () {
      final out = applySearchHighlight(
        const [TextSpan(text: 'halo dunia halo', style: base)],
        'halo',
      );
      final highlighted =
          out.where((s) => s.style?.backgroundColor != null).toList();
      expect(highlighted.length, 2);
      expect(highlighted.first.text, 'halo');
      // Style asal (warna teks) dipertahankan.
      expect(highlighted.first.style?.color, Colors.white);
    });

    test('tanpa cocok → satu span utuh', () {
      final out = applySearchHighlight(
        const [TextSpan(text: 'halo dunia', style: base)],
        'xyz',
      );
      expect(out.length, 1);
      expect(out.first.style?.backgroundColor, isNull);
    });

    test('case-insensitive, teks asli dipertahankan', () {
      final out = applySearchHighlight(
        const [TextSpan(text: 'HALO dunia', style: base)],
        'halo',
      );
      final highlighted =
          out.where((s) => s.style?.backgroundColor != null).toList();
      expect(highlighted.length, 1);
      expect(highlighted.first.text, 'HALO');
    });
  });
}
