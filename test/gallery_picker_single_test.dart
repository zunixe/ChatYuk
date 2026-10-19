import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/widgets/gallery_picker_sheet.dart';

/// Pemilih foto sekali-lihat (`maxSelect: 1`) TIDAK boleh menampilkan bulatan
/// nomor pemilih (UI multi-select) — foto langsung dikirim begitu diketuk.
void main() {
  testWidgets('mode pilih-tunggal: tanpa bulatan angka (single-select)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => Center(
                child: ElevatedButton(
                  onPressed: () => GalleryPickerSheet.show(
                    ctx,
                    s: S(isId: true),
                    maxSelect: 1,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // Bulatan angka '1' tidak boleh tampil di mode tunggal.
    expect(find.text('1'), findsNothing);
    expect(tester.takeException(), isNull);
    // Tombol kirim (multi) tidak tampil — single-select langsung kirim.
    // (Tidak ada `_sendButton`/`_folderButton` yang memakai teks 'Kirim'.)
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
}
