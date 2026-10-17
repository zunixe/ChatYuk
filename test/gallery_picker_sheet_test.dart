import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/widgets/gallery_picker_sheet.dart';

void main() {
  Future<GalleryPickResult?> openAnd(
    WidgetTester t,
    Future<void> Function() act,
  ) async {
    GalleryPickResult? out;
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 860);
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  out = await GalleryPickerSheet.show(ctx, s: S(isId: false));
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    // Spinner galeri berputar terus (plugin tak ada di test) → jangan
    // pumpAndSettle; pump durasi tetap cukup untuk animasi sheet.
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await t.pump(const Duration(milliseconds: 60));
      }
    }

    await t.tap(find.text('open'));
    await settle();
    await act();
    await settle();
    return out;
  }

  testWidgets('header ala WhatsApp: X, Recents, HD', (t) async {
    await openAnd(t, () async {});
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.text('Recents'), findsOneWidget);
    expect(find.text('HD'), findsOneWidget);
  });

  testWidgets('tombol folder -> pemilih sistem, HD ikut terbawa', (t) async {
    final r = await openAnd(t, () async {
      await t.tap(find.text('HD'));
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      await t.tap(find.byIcon(Icons.folder_open_rounded));
    });
    expect(r, isNotNull);
    expect(r!.useSystemPicker, isTrue);
    expect(r.hd, isTrue);
  });

  testWidgets('X menutup tanpa hasil', (t) async {
    final r = await openAnd(t, () => t.tap(find.byIcon(Icons.close)));
    expect(r, isNull);
  });
}
