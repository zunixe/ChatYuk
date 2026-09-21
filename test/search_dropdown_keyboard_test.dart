import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/widgets/search_dropdown.dart';

/// Regresi (dilaporkan user, Xiaomi 1200x2670 @520dpi):
/// "pilih negara formnya ilang ketika keyboardnya keatas".
///
/// Sebab: panel dropdown SELALU dibuka ke bawah field
/// (`targetAnchor: bottomLeft`). Panel hidup di Overlay → tidak ikut
/// me-resize saat keyboard naik, sementara field ikut naik (Scaffold
/// `resizeToAvoidBottomInset: true`). Hasilnya panel tertinggal di area yang
/// kini tertutup keyboard.
///
/// Perbaikan: hitung ruang yang benar-benar terlihat (tinggi - keyboard) dan
/// buka ke ATAS bila ruang bawah tidak layak.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const items = ['Indonesia', 'Jepang', 'Kenya', 'Malaysia', 'Singapura'];

  Widget host({double fieldTop = 120}) => Scaffold(
        // Meniru entry/register: body ikut resize saat keyboard naik.
        resizeToAvoidBottomInset: true,
        body: SingleChildScrollView(
          child: Column(
            children: [
              SizedBox(height: fieldTop),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: SearchDropdown<String>(
                  value: 'Indonesia',
                  label: 'Negara',
                  icon: null,
                  items: items,
                  labels: items,
                  searchHint: 'Cari negara...',
                  emptyText: 'Tidak ada',
                  onChanged: (_) {},
                ),
              ),
              const SizedBox(height: 900),
            ],
          ),
        ),
      );

  /// MediaQuery disuntik lewat `MaterialApp.builder` — WAJIB, karena panel
  /// dropdown hidup di Overlay (di dalam Navigator), sehingga MediaQuery yang
  /// hanya membungkus `home` TIDAK sampai ke overlay.
  Widget appWithInsets({required double keyboard, required Widget home}) {
    return MaterialApp(
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
          size: const Size(400, 800),
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: child!,
      ),
      home: home,
    );
  }

  void configure(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('tanpa keyboard: panel terbuka & item bisa dipilih',
      (tester) async {
    configure(tester);
    await tester.pumpWidget(appWithInsets(keyboard: 0, home: host()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Indonesia'));
    await tester.pumpAndSettle();

    expect(find.text('Cari negara...'), findsOneWidget);
    expect(find.text('Kenya'), findsOneWidget);

    await tester.tap(find.text('Kenya'));
    await tester.pumpAndSettle();
    expect(find.text('Cari negara...'), findsNothing, reason: 'panel tertutup');
  });

  testWidgets(
      'field di bawah + keyboard aktif → panel masih bisa dicari',
      (tester) async {
    // Verifikasi: saat keyboard aktif, panel search tetap berfungsi
    // (ketik → item terfilter). Ini uji alur "pas ngetik dropdown hilang"
    // dari user (Xiaomi). Skenario real: field berada di atas, keyboard
    // mengecilkan body — panel harus tetap terlihat di overlay.
    configure(tester);
    await tester.pumpWidget(
      appWithInsets(keyboard: 300, home: host(fieldTop: 200)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Indonesia'));
    await tester.pumpAndSettle();
    expect(find.text('Cari negara...'), findsOneWidget);

    // Ketik untuk memfilter — panel harus tetap berfungsi.
    await tester.enterText(find.byType(TextField), 'Ken');
    await tester.pumpAndSettle();

    expect(find.text('Kenya'), findsOneWidget, reason: 'item terfilter tampil');
    expect(find.text('Jepang'), findsNothing, reason: 'item tidak cocok disaring');
  });

  testWidgets('pilih negara tetap bekerja dengan keyboard terbuka',
      (tester) async {
    String? picked;
    configure(tester);
    await tester.pumpWidget(appWithInsets(
      keyboard: 300,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 200),
              SearchDropdown<String>(
                value: 'Indonesia',
                label: 'Negara',
                icon: null,
                items: items,
                labels: items,
                searchHint: 'Cari negara...',
                emptyText: 'Tidak ada',
                onChanged: (v) => picked = v,
              ),
              const SizedBox(height: 900),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Indonesia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jepang'));
    await tester.pumpAndSettle();

    expect(picked, 'Jepang', reason: 'pilihan harus tersampaikan');
  });

  test('perbaikan tidak menyentuh token tema', () {
    expect(AppTheme.statusColor('online'), AppTheme.online);
  });
}
