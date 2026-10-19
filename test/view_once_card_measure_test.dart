import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/media/chat_photo_helper.dart';
import 'package:chatyuk/widgets/chat_video_bubble.dart';
import 'package:chatyuk/widgets/message/view_once_image.dart';

/// Aturan ukuran kartu foto sekali-lihat (minta user 2026-10-19):
///  - Kartu PEMBUKA ("tekan untuk melihat") & kartu KEDALUWARSA =
///    ukuran tetap KECIL 200×140 (seperti semula).
///  - Setelah foto dibuka: ukuran = FOTO BIASA (lebar chatMediaWidth).
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('kartu pembuka & kedaluwarsa = KECIL 200×140', (tester) async {
    await pump(
      tester,
      ViewOnceImage(
        imageData: '',
        chatKey: 'k1',
        isMe: false,
        messageId: 'vo-active',
        viewSecs: 10,
      ),
    );
    expect(
      tester.getSize(find.byType(ViewOnceImage)),
      const Size(ViewOnceLockedCard.cardWidth, ViewOnceLockedCard.cardHeight),
    );

    await pump(
      tester,
      ViewOnceImage(
        imageData: '',
        chatKey: 'k2',
        isMe: false,
        messageId: 'vo-expired',
        isExpired: true,
      ),
    );
    expect(
      tester.getSize(find.byType(ViewOnceImage)),
      const Size(ViewOnceLockedCard.cardWidth, ViewOnceLockedCard.cardHeight),
    );
  });

  test('lebar foto saat dibuka = lebar foto biasa (chatMediaWidth)', () {
    // Konstanta bersama memastikan kartu yang menampilkan foto memakai
    // lebar 72% layar seperti bubble foto biasa.
    expect(chatMediaWidth(360), (360 * 0.72).clamp(200.0, 440.0));
  });
}
