import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/media/chat_photo_helper.dart';
import 'package:chatyuk/widgets/chat_video_bubble.dart';
import 'package:chatyuk/widgets/message/view_once_image.dart';

/// Aturan final (minta user):
///  - Kartu bertulisan "Foto Sekali Lihat" (pembuka) & "Foto sudah
///    kadaluarsa" = KECIL 200×140 seperti semula.
///  - Kartu yang MENAMPILKAN foto = lebar foto biasa (chatMediaWidth).
void main() {
  Future<Size> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: child),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    return tester.getSize(find.byType(ViewOnceImage));
  }

  testWidgets('pembuka & kedaluwarsa = KECIL 200×140', (tester) async {
    const small = Size(
      ViewOnceLockedCard.cardWidth,
      ViewOnceLockedCard.cardHeight,
    );

    final idle = await pump(
      tester,
      ViewOnceImage(
        imageData: '',
        chatKey: 'k1',
        isMe: false,
        messageId: 'vo-idle',
        viewSecs: 10,
      ),
    );
    expect(idle, small, reason: 'kartu "Foto Sekali Lihat" harus kecil');

    final expired = await pump(
      tester,
      ViewOnceImage(
        imageData: '',
        chatKey: 'k2',
        isMe: false,
        messageId: 'vo-exp',
        isExpired: true,
      ),
    );
    expect(expired, small, reason: 'kartu "sudah kadaluarsa" harus kecil');
  });

  testWidgets('kartu pengirim (menampilkan foto) = lebar foto biasa', (
    tester,
  ) async {
    final screenW =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final size = await pump(
      tester,
      ViewOnceImage(
        imageData: '',
        chatKey: 'k3',
        isMe: true,
        messageId: 'vo-me',
        viewSecs: 10,
      ),
    );
    expect(size.width, chatMediaWidth(screenW));
  });
}
