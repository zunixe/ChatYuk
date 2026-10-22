import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/message/image_decode_core.dart';
import 'package:chatyuk/widgets/message/view_once_image.dart';
import 'package:chatyuk/widgets/message/view_once_state.dart';

// PNG 1x1 valid — cukup untuk viewer.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

/// Bug 2026-10-22: timer sekali-lihat habis SAAT bubble pemulainya sudah
/// dibuang (rebuild list / keluar chat) → `_expireNow` berhenti di
/// `!mounted` → kartu tak pernah terkunci, foto bisa dibuka berulang.
void main() {
  testWidgets('timer habis setelah bubble dibuang → tetap expired', (
    tester,
  ) async {
    // id `pending-` → penanda server di-skip (tanpa Supabase di test).
    const id = 'pending-vo-unmount';
    final tick = putViewOnceState(id, ViewOnceTick());
    tick.decoded = DecodedImage(_png, 1, 1);

    Widget app({required bool showBubble}) => ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: showBubble
                    ? const ViewOnceImage(
                        imageData: '',
                        chatKey: 'private_x',
                        isMe: false,
                        messageId: id,
                        viewSecs: 3,
                      )
                    : const SizedBox(),
              ),
            ),
          ),
        );

    await tester.pumpWidget(app(showBubble: true));
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();
    expect(tick.state, ViewOnceState.viewing);
    expect(tick.timer, isNotNull);

    // Bubble dibuang selagi countdown berjalan.
    await tester.pumpWidget(app(showBubble: false));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    expect(tick.state, ViewOnceState.expired);
    expect(tick.decoded, isNull);
    expect(tick.viewerOpen, isFalse);
    viewOnceStates.remove(id);
  });
}
