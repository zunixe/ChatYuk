import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/widgets/message/message_image.dart';
import 'package:chatyuk/widgets/photo_album_bubble.dart';

/// Mengunci tata letak album ala WhatsApp: kotak persegi 72% lebar layar,
/// 2 = berdampingan, 3 = 1 besar kiri + 2 kanan, 4+ = grid 2×2.
void main() {
  final b64 = base64Encode(
    Uint8List.fromList(img.encodeJpg(img.Image(width: 400, height: 800))),
  );
  MessageModel photo(String id) => MessageModel(
    id: id,
    senderId: 'u1',
    senderName: 'A',
    senderGender: 'male',
    isRegistered: true,
    text: '',
    type: 'image',
    imageData: b64,
    timestamp: DateTime(2026, 10, 17, 12),
    albumId: 'X',
  );

  Future<List<Size>> pump(WidgetTester t, int n) async {
    // 360dp → sisi album 72% = 259.2
    t.view.devicePixelRatio = 3.0;
    t.view.physicalSize = const Size(1080, 2400);
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: PhotoAlbumBubble(
                photos: [for (var i = 0; i < n; i++) photo('p$n-$i')],
                chatKey: 'private_a_b',
                timeStr: '4:10 PM',
              ),
            ),
          ),
        ),
      ),
    );
    return t
        .widgetList<MessageImage>(find.byType(MessageImage))
        .map((w) => t.getSize(find.byWidget(w)))
        .toList();
  }

  const side = 360 * 0.72;
  const half = (side - 3) / 2;

  testWidgets('2 foto: dua kotak tegak berdampingan', (t) async {
    final s = await pump(t, 2);
    expect(s.length, 2);
    for (final z in s) {
      expect(z.width, closeTo(half, 0.01));
      expect(z.height, closeTo(side, 0.01));
    }
  });

  testWidgets('3 foto: 1 besar kiri + 2 bertumpuk kanan', (t) async {
    final s = await pump(t, 3);
    expect(s[0].height, closeTo(side, 0.01));
    expect(s[1].height, closeTo(half, 0.01));
    expect(s[2].height, closeTo(half, 0.01));
    for (final z in s) {
      expect(z.width, closeTo(half, 0.01));
    }
  });

  testWidgets('5 foto: grid 2×2 + overlay +1', (t) async {
    final s = await pump(t, 5);
    expect(s.length, 4);
    for (final z in s) {
      expect(z.width, closeTo(half, 0.01));
      expect(z.height, closeTo(half, 0.01));
    }
    expect(find.text('+1'), findsOneWidget);
  });
}
