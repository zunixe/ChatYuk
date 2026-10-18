import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/widgets/photo_album_bubble.dart';
import 'package:chatyuk/widgets/message/message_image.dart';

/// Regresi permintaan user (2026-10-18): waktu album harus di BAWAH foto,
/// di DALAM card, rata KANAN — sama seperti bubble pesan lain.
///
/// Sebelumnya jam ditumpuk sebagai pill DI ATAS foto (overlay), sehingga
/// tidak sejajar dengan waktu bubble lain.
void main() {
  final b64 = base64Encode(
    Uint8List.fromList(img.encodeJpg(img.Image(width: 400, height: 800))),
  );

  MessageModel photo(String id, {String caption = ''}) => MessageModel(
    id: id,
    senderId: 'u1',
    senderName: 'A',
    senderGender: 'male',
    isRegistered: true,
    text: caption,
    type: 'image',
    imageData: b64,
    timestamp: DateTime(2026, 10, 18, 12),
    albumId: 'X',
  );

  Future<void> pump(
    WidgetTester t, {
    String caption = '',
    bool showChecks = true,
  }) async {
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
                photos: [
                  photo('p1', caption: caption),
                  photo('p2', caption: caption),
                ],
                chatKey: 'private_a_b',
                timeStr: '4:10 PM',
                showChecks: showChecks,
                isMe: true,
                cardColor: const Color(0xFF1F2A3A),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('waktu TIDAK lagi menumpuk di atas foto', (t) async {
    await pump(t);
    final timeRect = t.getRect(find.text('4:10 PM'));
    final gridRect = t.getRect(find.byType(MessageImage).first);

    // Grid = kotak persegi foto. Waktu harus DI BAWAH grid, bukan menumpuk.
    expect(
      timeRect.top,
      greaterThanOrEqualTo(gridRect.bottom - 1),
      reason: 'jam harus di bawah foto (bukan overlay di atasnya)',
    );
  });

  testWidgets('waktu rata kanan (nempel tepi kanan card)', (t) async {
    // Tanpa centang: agar yang diukur benar-benar tepi kanan JAM.
    await pump(t, showChecks: false);
    final timeRect = t.getRect(find.text('4:10 PM'));
    // Acuan = tepi kanan CARD album (bukan tile kiri).
    final cardRect = t.getRect(find.byType(PhotoAlbumBubble));

    expect(
      cardRect.right - timeRect.right,
      lessThan(16),
      reason: 'jam harus rata kanan (padding card 4 + padding 2) — '
          'terukur ${cardRect.right - timeRect.right}',
    );
  });

  testWidgets('dengan caption: caption di kiri, jam tetap rata kanan', (
    t,
  ) async {
    // Tanpa centang: jam sendiri yang harus nempel tepi kanan.
    await pump(t, caption: 'liburan seru', showChecks: false);
    final capRect = t.getRect(find.textContaining('liburan', findRichText: true));
    final timeRect = t.getRect(find.text('4:10 PM'));
    final gridRect = t.getRect(find.byType(MessageImage).first);
    final cardRect = t.getRect(find.byType(PhotoAlbumBubble));

    // Caption & jam sama-sama di bawah foto.
    expect(capRect.top, greaterThanOrEqualTo(gridRect.bottom - 1));
    expect(timeRect.top, greaterThanOrEqualTo(gridRect.bottom - 1));
    // Caption di KIRI, jam di KANAN.
    expect(capRect.left, lessThan(timeRect.left));
    expect(cardRect.right - timeRect.right, lessThan(16));
  });

  testWidgets('centang tampil di bawah foto untuk pesan sendiri', (t) async {
    await pump(t, showChecks: true);
    final gridRect = t.getRect(find.byType(MessageImage).first);
    final check = find.byIcon(Icons.done_all);
    expect(check, findsOneWidget);
    expect(t.getRect(check).top, greaterThanOrEqualTo(gridRect.bottom - 1));
  });
}
