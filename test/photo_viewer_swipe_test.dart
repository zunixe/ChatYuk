import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/message/photo_viewer_screen.dart';

/// Viewer multi-foto: swipe VERTIKAL antar foto (ala WhatsApp — geser ke atas
/// = foto berikutnya). Test memastikan:
///  1. mode multi memasang PageView vertikal,
///  2. indikator "1/N" tampil dan ikut berubah,
///  3. swipe ke atas benar-benar pindah ke foto berikutnya,
///  4. satu foto (photos null) TIDAK memasang PageView → tak ada swipe.
void main() {
  // PNG 1×1 transparan (valid untuk Image.memory).
  final Uint8List png = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  Future<void> pump(WidgetTester t, {List<ViewerPhoto>? photos, int at = 0}) {
    return t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: PhotoViewerScreen(
            bytes: png,
            photos: photos,
            initialIndex: at,
          ),
        ),
      ),
    );
  }

  List<ViewerPhoto> gallery(int n) => [
    for (var i = 0; i < n; i++) ViewerPhoto(bytes: png),
  ];

  testWidgets('multi-foto: PageView vertikal + indikator 1/N', (t) async {
    await pump(t, photos: gallery(3));
    await t.pump();

    final pv = t.widget<PageView>(find.byType(PageView));
    expect(pv.scrollDirection, Axis.vertical);
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('swipe ke atas = foto berikutnya', (t) async {
    await pump(t, photos: gallery(3));
    await t.pump();

    // Geser ke ATAS (dy negatif) — arah "slide keatas" seperti WhatsApp.
    await t.drag(find.byType(PageView), const Offset(0, -500));
    await t.pumpAndSettle();

    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('swipe ke bawah = foto sebelumnya', (t) async {
    await pump(t, photos: gallery(3), at: 1);
    await t.pump();
    expect(find.text('2/3'), findsOneWidget);

    await t.drag(find.byType(PageView), const Offset(0, 500));
    await t.pumpAndSettle();

    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('buka dari foto ke-3 → mulai di 3/3', (t) async {
    await pump(t, photos: gallery(4), at: 2);
    await t.pump();
    expect(find.text('3/4'), findsOneWidget);
  });

  testWidgets('satu foto: tanpa PageView, gambar tetap tampil', (t) async {
    await pump(t);
    await t.pump();

    expect(find.byType(PageView), findsNothing);
    expect(find.byType(Image), findsWidgets);
    // Tidak ada indikator N/M untuk satu foto.
    expect(find.textContaining('/1'), findsNothing);
  });
}
