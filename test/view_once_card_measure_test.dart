import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/chat_video_bubble.dart';
import 'package:chatyuk/widgets/message/view_once_image.dart';

/// Ukur NYATA: kartu foto sekali-lihat (masih bisa dilihat) harus SAMA
/// ukurannya dengan kartu foto kedaluwarsa.
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

  testWidgets('kartu foto sekali-lihat = kartu kedaluwarsa (200×140)', (
    tester,
  ) async {
    // Aktif (belum decode → pakai ukuran kartu).
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
    expect(active.width, ViewOnceLockedCard.cardWidth);
    expect(active.height, ViewOnceLockedCard.cardHeight);

    // Kedaluwarsa.
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
    expect(expired.width, ViewOnceLockedCard.cardWidth);
    expect(expired.height, ViewOnceLockedCard.cardHeight);

    // Bukti inti keluhan: kedua kartu SAMA.
    expect(active, expired);
  });
}
