import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/chat/chat_file.dart';
import 'package:chatyuk/core/chat/pending_confirm.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/widgets/message/file_bubble.dart';

MessageModel _file(String id, String name, {DateTime? at, int size = 1500}) =>
    MessageModel(
      id: id,
      senderId: 'u1',
      senderName: 'A',
      senderGender: 'male',
      isRegistered: true,
      text: name,
      type: 'file',
      imageData: 'chat/c1/1_f.pdf',
      timestamp: at ?? DateTime(2026, 10, 17, 12),
      durationMs: size,
    );

void main() {
  group('ChatFile', () {
    test('ekstensi & mime', () {
      expect(ChatFile.extOf('Laporan.PDF'), 'pdf');
      expect(ChatFile.extOf('tanpaekstensi'), '');
      expect(ChatFile.mimeOf('a.pdf'), 'application/pdf');
      expect(ChatFile.mimeOf('a.xyz'), 'application/octet-stream');
    });

    test('label ukuran', () {
      expect(ChatFile.sizeLabel(500), '500 B');
      expect(ChatFile.sizeLabel(12 * 1024), '12 KB');
      expect(ChatFile.sizeLabel((1.4 * 1024 * 1024).round()), '1.4 MB');
      expect(ChatFile.sizeLabel(25 * 1024 * 1024), '25 MB');
    });

    test('ikon per jenis', () {
      expect(ChatFile.styleOf('a.pdf').icon, Icons.picture_as_pdf_rounded);
      expect(ChatFile.styleOf('a.docx').icon, Icons.description_rounded);
      expect(ChatFile.styleOf('a.zzz').icon, Icons.insert_drive_file_rounded);
    });

    test('registry path lokal bounded 50', () {
      for (var i = 0; i < 60; i++) {
        ChatFile.rememberLocal('k$i', '/p$i');
      }
      expect(ChatFile.localPathOf('k0'), isNull);
      expect(ChatFile.localPathOf('k59'), '/p59');
    });
  });

  group('consumeConfirmedFile', () {
    final opened = DateTime(2026, 10, 17, 11);
    test('gema server membuang pending dengan nama sama, sekali pakai', () {
      final pend = [_file('pending-1', 'a.pdf'), _file('pending-2', 'b.pdf')];
      final used = <String>{};
      final srv = _file('99', 'b.pdf');
      expect(
        consumeConfirmedFile(
          server: srv,
          openedAt: opened,
          consumedIds: used,
          pendings: pend,
        ),
        1,
      );
      expect(
        consumeConfirmedFile(
          server: srv,
          openedAt: opened,
          consumedIds: used,
          pendings: pend,
        ),
        -1,
      );
    });

    test('history sebelum layar dibuka diabaikan', () {
      final idx = consumeConfirmedFile(
        server: _file('5', 'a.pdf', at: DateTime(2026, 10, 17, 10)),
        openedAt: opened,
        consumedIds: <String>{},
        pendings: [_file('pending-1', 'a.pdf')],
      );
      expect(idx, -1);
    });
  });

  testWidgets('FileBubble: nama, jenis + ukuran, status kirim', (t) async {
    Future<void> pump(bool pending) => t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: FileBubble(
              msg: _file('m1', 'Laporan Q3.pdf', size: 12 * 1024),
              timeStr: '4:10 PM',
              isMe: true,
              showChecks: true,
              isPending: pending,
            ),
          ),
        ),
      ),
    );
    await pump(false);
    expect(find.text('Laporan Q3.pdf'), findsOneWidget);
    expect(find.text('PDF · 12 KB'), findsOneWidget);
    expect(find.byIcon(Icons.picture_as_pdf_rounded), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
    await pump(true);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
