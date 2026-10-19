import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/widgets/message/view_once_image.dart';
import 'package:chatyuk/widgets/message/view_once_state.dart';

/// (1) Label durasi HANYA muncul bila memang bertimer (bukan hardcode 10).
/// (2) Foto yang SUDAH kedaluwarsa tidak "blink" isinya saat masuk chat.
void main() {
  group('label durasi sekali-lihat', () {
    test('10 detik → tulis 10 detik', () {
      expect(S(isId: true).viewOnceTap(10), 'Tekan untuk melihat (10 detik)');
      expect(S(isId: false).viewOnceTap(10), 'Tap to view (10 seconds)');
    });

    test('durasi lain mengikuti nilai nyata', () {
      expect(S(isId: true).viewOnceTap(30), contains('30 detik'));
      expect(S(isId: true).viewOnceTap(5), contains('5 detik'));
    });

    test('mode 1× (tanpa timer) tidak menyebut detik', () {
      expect(S(isId: true).viewOnceTap(0), 'Tekan untuk melihat');
      expect(S(isId: true).viewOnceTap(0).contains('detik'), isFalse);
    });
  });

  testWidgets('expired: langsung kartu terkunci, tidak menampilkan isi foto', (
    tester,
  ) async {
    // Siapkan state cache yang masih "idle" untuk id ini — kasus nyata:
    // foto pernah dibuka, chat ditutup, server menandai kedaluwarsa.
    final id = 'vo-blink-test';
    final tick = putViewOnceState(id, ViewOnceTick());
    tick.state = ViewOnceState.idle;
    tick.decoded = null;

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ViewOnceImage(
                imageData: '',
                chatKey: 'k',
                isMe: false,
                messageId: id,
                isExpired: true,
              ),
            ),
          ),
        ),
      ),
    );
    // Frame PERTAMA sudah harus terkunci (tidak ada state idle/viewing).
    expect(tick.state, ViewOnceState.expired);
    expect(tick.decoded, isNull);
    await tester.pump();
    expect(tick.state, ViewOnceState.expired);
  });
}
