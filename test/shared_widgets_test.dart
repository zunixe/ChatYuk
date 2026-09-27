import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/core/admin_err.dart';
import 'package:chatyuk/widgets/admin_error_view.dart';
import 'package:chatyuk/widgets/detail_row.dart';
import 'package:chatyuk/widgets/filter_chip_pill.dart';
import 'package:chatyuk/widgets/initial_avatar.dart';
import 'package:chatyuk/widgets/search_field.dart';
import 'package:chatyuk/widgets/sheet_drag_handle.dart';
import 'package:chatyuk/widgets/toggle_tile.dart';

import 'test_helper.dart';

/// Fase 3 — widget bersama hasil refactor Fase C (admin & user).
/// Mengunci kontrak agar konsolidasi tidak diam-diam berubah perilaku.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    AppFonts.setLocal(AppFonts.systemKey);
  });
  tearDownAll(resetFontForTest);

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
    await tester.pump();
  }

  group('DetailRow', () {
    testWidgets('labelWidth null → label Expanded (nilai di kanan)',
        (tester) async {
      await pump(tester, const DetailRow('Nama', 'Budi'));
      expect(find.text('Nama'), findsOneWidget);
      expect(find.text('Budi'), findsOneWidget);
      // Label dibungkus Expanded (bukan SizedBox lebar tetap).
      expect(
        find.ancestor(
          of: find.text('Nama'),
          matching: find.byType(Expanded),
        ),
        findsOneWidget,
      );
    });

    testWidgets('labelWidth diisi → label lebar tetap', (tester) async {
      await pump(tester, const DetailRow('K', 'V', labelWidth: 110));
      expect(find.text('K'), findsOneWidget);
      expect(find.text('V'), findsOneWidget);
      final box = tester.widget<SizedBox>(
        find.ancestor(of: find.text('K'), matching: find.byType(SizedBox)).first,
      );
      expect(box.width, 110);
    });
  });

  group('SheetDragHandle', () {
    testWidgets('render garis 40 lebar (isi 4 + margin atas 10)', (tester) async {
      await pump(tester, const SheetDragHandle());
      final size = tester.getSize(
        find.descendant(
          of: find.byType(SheetDragHandle),
          matching: find.byType(Container),
        ),
      );
      expect(size.width, 40);
      // RenderBox termasuk margin-container (atas 10) → tinggi = 4 + 10.
      expect(size.height, 14);
      // Properti bar-nya sendiri harus 40x4.
      final c = tester.widget<Container>(
        find.descendant(
          of: find.byType(SheetDragHandle),
          matching: find.byType(Container),
        ),
      );
      expect(c.constraints?.maxWidth, 40);
      expect(c.constraints?.maxHeight, 4);
    });
  });

  group('InitialAvatarBox / Circle', () {
    testWidgets('Box: huruf pertama uppercase + ukuran', (tester) async {
      await pump(tester, const InitialAvatarBox(name: 'budi', size: 40));
      expect(find.text('B'), findsOneWidget);
      final size = tester.getSize(find.byType(Container).first);
      expect(size.width, 40);
    });

    testWidgets('nama kosong → "?"', (tester) async {
      await pump(tester, const InitialAvatarBox(name: ''));
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('Circle: inisial tampil', (tester) async {
      await pump(tester, const InitialAvatarCircle(name: 'sari'));
      expect(find.text('S'), findsOneWidget);
      expect(find.byType(CircleAvatar), findsOneWidget);
    });
  });

  group('AdminErrorView', () {
    testWidgets('menampilkan teks error + tombol coba lagi → onRetry dipanggil',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        AdminErrorView(
          s: S(isId: true),
          error: AdminErrKind.offline,
          onRetry: () => taps++,
        ),
      );
      expect(taps, 0);
      await tester.tap(find.byType(ElevatedButton));
      await tester.pump();
      expect(taps, 1);
    });
  });

  group('ToggleTile', () {
    testWidgets('tap switch → onChanged(true)', (tester) async {
      bool? got;
      await pump(
        tester,
        ToggleTile(
          icon: Icons.abc,
          color: Colors.green,
          title: 'Judul',
          desc: 'Deskripsi',
          value: false,
          onChanged: (v) => got = v,
        ),
      );
      expect(find.text('Judul'), findsOneWidget);
      expect(find.text('Deskripsi'), findsOneWidget);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(got, isTrue);
    });
  });

  group('SearchField', () {
    testWidgets('mengetik → onChanged menerima teks', (tester) async {
      final ctrl = TextEditingController();
      addTearDown(ctrl.dispose);
      String? typed;
      await pump(
        tester,
        SearchField(controller: ctrl, onChanged: (v) => typed = v, hint: 'Cari'),
      );
      expect(find.text('Cari'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'halo');
      await tester.pump();
      expect(typed, 'halo');
    });
  });

  group('FilterChipPill', () {
    testWidgets('tanpa count → label saja; tap memanggil onTap',
        (tester) async {
      var taps = 0;
      await pump(
        tester,
        FilterChipPill(label: 'Semua', active: true, onTap: () => taps++),
      );
      expect(find.text('Semua'), findsOneWidget);
      await tester.tap(find.text('Semua'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('dengan count → label "X (n)"', (tester) async {
      await pump(
        tester,
        FilterChipPill(
          label: 'Anon',
          count: 7,
          active: false,
          onTap: () {},
        ),
      );
      expect(find.text('Anon (7)'), findsOneWidget);
    });
  });
}
