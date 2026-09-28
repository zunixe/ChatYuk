import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/chat/pending_confirm.dart';
import 'package:chatyuk/models/message_model.dart';

/// Mengunci dedupe bubble optimistik: pesan lama yang sama isinya TIDAK
/// boleh membuang pending baru ("kirim lalu hilang, muncul telat").
void main() {
  MessageModel textMsg(
    String id,
    String text,
    DateTime ts, {
    String sender = 'me',
    String type = 'text',
  }) {
    return MessageModel(
      id: id,
      senderId: sender,
      senderName: 'Me',
      senderGender: 'other',
      isRegistered: true,
      text: text,
      type: type,
      imageData: '',
      timestamp: ts,
    );
  }

  final openedAt = DateTime.utc(2026, 9, 28, 10, 0, 0);
  MessageModel pending(String id, String text) => textMsg(
        id,
        text,
        openedAt.add(const Duration(seconds: 1)),
      );

  group('consumeConfirmedText', () {
    test('gema fresh memakai pending tertua (FIFO)', () {
      final pendings = [pending('p1', 'ok'), pending('p2', 'ok')];
      final consumed = <String>{};
      final echo = textMsg(
        's1',
        'ok',
        openedAt.add(const Duration(seconds: 2)),
      );
      expect(
        consumeConfirmedText(
          server: echo,
          openedAt: openedAt,
          consumedIds: consumed,
          pendings: pendings,
        ),
        0,
      );
      expect(consumed, contains('s1'));
    });

    test('id server yang sama tidak memakai 2× (ketik 2× aman)', () {
      final pendings = [pending('p1', 'ok'), pending('p2', 'ok')];
      final consumed = <String>{};
      final echo = textMsg(
        's1',
        'ok',
        openedAt.add(const Duration(seconds: 2)),
      );
      consumeConfirmedText(
        server: echo,
        openedAt: openedAt,
        consumedIds: consumed,
        pendings: pendings,
      );
      pendings.removeAt(0);
      // Emisi ulang daftar yang sama → s1 sudah terpakai, p2 AMAN.
      expect(
        consumeConfirmedText(
          server: echo,
          openedAt: openedAt,
          consumedIds: consumed,
          pendings: pendings,
        ),
        -1,
      );
      expect(pendings.length, 1);
      // Gema kedua memakai pending kedua.
      final echo2 = textMsg(
        's2',
        'ok',
        openedAt.add(const Duration(seconds: 3)),
      );
      expect(
        consumeConfirmedText(
          server: echo2,
          openedAt: openedAt,
          consumedIds: consumed,
          pendings: pendings,
        ),
        0,
      );
    });

    test('pesan lama (sebelum buka) tidak membuang pending baru', () {
      final pendings = [pending('p1', 'ok')];
      final consumed = <String>{};
      final old = textMsg(
        'sold',
        'ok',
        openedAt.subtract(const Duration(days: 1)),
      );
      expect(
        consumeConfirmedText(
          server: old,
          openedAt: openedAt,
          consumedIds: consumed,
          pendings: pendings,
        ),
        -1,
      );
      expect(pendings.length, 1);
      // Gema asli tetap bisa memakai pending.
      final echo = textMsg(
        's1',
        'ok',
        openedAt.add(const Duration(seconds: 2)),
      );
      expect(
        consumeConfirmedText(
          server: echo,
          openedAt: openedAt,
          consumedIds: consumed,
          pendings: pendings,
        ),
        0,
      );
    });

    test('server tanpa pending cocok tetap ditandai (kirim dari device lain)', () {
      final pendings = <MessageModel>[];
      final consumed = <String>{};
      final foreign = textMsg(
        's9',
        'ok',
        openedAt.add(const Duration(seconds: 2)),
      );
      expect(
        consumeConfirmedText(
          server: foreign,
          openedAt: openedAt,
          consumedIds: consumed,
          pendings: pendings,
        ),
        -1,
      );
      expect(consumed, contains('s9'));
      // Pending identik yang dikirim belakangan tidak dimakan s9.
      pendings.add(pending('p1', 'ok'));
      expect(
        consumeConfirmedText(
          server: foreign,
          openedAt: openedAt,
          consumedIds: consumed,
          pendings: pendings,
        ),
        -1,
      );
      expect(pendings.length, 1);
    });

    test('bukan teks → -1', () {
      final pendings = [pending('p1', 'ok')];
      final img = textMsg(
        's1',
        'ok',
        openedAt.add(const Duration(seconds: 2)),
        type: 'image',
      );
      expect(
        consumeConfirmedText(
          server: img,
          openedAt: openedAt,
          consumedIds: <String>{},
          pendings: pendings,
        ),
        -1,
      );
      expect(pendings.length, 1);
    });
  });
}
