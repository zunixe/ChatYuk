import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/media/chat_photo_helper.dart';
import 'package:chatyuk/widgets/message/view_once_image.dart';

/// Kartu foto sekali-lihat WAJIB berukuran SAMA dengan kartu FOTO BIASA
/// (lebar `chatMediaWidth` = 72% layar), bukan kartu kecil "Foto Sekali Lihat".
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

  testWidgets('kartu aktif & kedaluwarsa = lebar kartu foto biasa', (
    tester,
  ) async {
    final screenW =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final expectedW = chatMediaWidth(screenW);

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
    final active = tester.getSize(find.byType(ViewOnceImage));
    expect(active.width, expectedW, reason: 'lebar = lebar foto biasa');

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
    final expired = tester.getSize(find.byType(ViewOnceImage));
    expect(expired.width, expectedW);
    expect(expired.height, expectedW * 4 / 3);

    // Inti keluhan: kartu pembuka & kartu kedaluwarsa sama ukuran.
    expect(active, expired);
  });
}
