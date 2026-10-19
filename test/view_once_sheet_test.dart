import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/message/view_once_sheet.dart';

/// Viewer foto sekali-lihat gaya GALERI (slide dari bawah), TANPA tombol HD:
/// kualitas foto ditentukan saat KIRIM (toggle HD di preview composer).
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
  testWidgets('sheet galeri: gambar + tutup, TANPA tombol HD', (tester) async {
    var closed = 0;
    await tester.pumpWidget(_app(onOpen: () => closed++));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Sheet tampil dari bawah: gambar & tombol tutup ada.
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    // Tombol HD TIDAK boleh ada di viewer (keputusan HD saat kirim).
    expect(find.text('HD'), findsNothing);

    // Tutup → sheet hilang + onClosed dipanggil (pemanggil mengunci foto 1x).
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(closed, 1);
  });

  test('payload dasar valid', () {
    expect(Uint8List.fromList(base64Decode(_png1x1)).isNotEmpty, isTrue);
  });
}
