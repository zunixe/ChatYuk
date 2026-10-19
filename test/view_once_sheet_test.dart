import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/message/view_once_sheet.dart';

/// Viewer foto sekali-lihat gaya GALERI (slide dari bawah) + tombol HD.
const _png1x1 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==';

Widget _app({required VoidCallback onOpen}) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () => showViewOnceSheet(
              context: ctx,
              bytes: base64Decode(_png1x1),
              fullLoader: () async => _png1x1,
              onClosed: onOpen,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('sheet galeri: gambar + tombol HD + tutup', (tester) async {
    var closed = 0;
    await tester.pumpWidget(_app(onOpen: () => closed++));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Sheet tampil dari bawah: ada handle, gambar, tombol HD & tombol tutup.
    expect(find.text('HD'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);

    // Tap HD → loader full-res dipanggil (decode native tak ada di test →
    // jalur gagal ditangani: snackbar, tanpa exception). JANGAN pumpAndSettle
    // (snackbar punya timer → tak pernah settle).
    await tester.tap(find.text('HD'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);

    // Tutup → sheet hilang + onClosed dipanggil (pemanggil mengunci foto 1x).
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('HD'), findsNothing);
    expect(closed, 1);
  });

  test('payload dasar valid', () {
    expect(Uint8List.fromList(base64Decode(_png1x1)).isNotEmpty, isTrue);
  });
}
