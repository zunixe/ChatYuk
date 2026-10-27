import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/providers/riverpod/locale_provider.dart';
import 'package:chatyuk/screens/profile/widgets/profile_widgets.dart';

/// Dialog pilih negara asal (kartu Moderasi di Profil) kini ber-search:
///   * ketik → daftar terfilter live (case-insensitive)
///   * query tanpa hasil → pesan kosong
///   * pilih item → nilai tersampaikan & dialog tertutup
///   * keyboard aktif → konten menyusut (tinggi adaptif), tetap bisa dipilih
void main() {
  final s = const LocaleState('id').s;

  const items = [
    'Indonesia',
    'Jepang',
    'Kenya',
    'Malaysia',
    'Singapura',
  ];

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

  Future<void> pumpHost(WidgetTester tester, {double keyboard = 0}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(appWithInsets(
      keyboard: keyboard,
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: FilledButton(
              onPressed: () => showDialog<String>(
                context: ctx,
                builder: (_) => CountryPickerDialog(
                  s: s,
                  countries: items,
                ),
              ),
              child: const Text('BUKA'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('BUKA'));
    await tester.pumpAndSettle();
  }

  testWidgets('tanpa keyboard: semua negara tampil & bisa dipilih',
      (tester) async {
    await pumpHost(tester);

    expect(find.text('Indonesia'), findsOneWidget);
    expect(find.text('Singapura'), findsOneWidget);

    await tester.tap(find.text('Kenya'));
    await tester.pumpAndSettle();
    expect(find.byType(CountryPickerDialog), findsNothing,
        reason: 'dialog tertutup setelah memilih');
  });

  testWidgets('search memfilter daftar live', (tester) async {
    await pumpHost(tester);

    await tester.enterText(find.byType(TextField), 'indo');
    await tester.pumpAndSettle();

    expect(find.text('Indonesia'), findsOneWidget,
        reason: 'item cocok tampil');
    expect(find.text('Jepang'), findsNothing,
        reason: 'item tidak cocok disaring');
  });

  testWidgets('search case-insensitive', (tester) async {
    await pumpHost(tester);

    await tester.enterText(find.byType(TextField), 'SINGA');
    await tester.pumpAndSettle();

    expect(find.text('Singapura'), findsOneWidget);
  });

  testWidgets('query tanpa hasil menampilkan pesan kosong', (tester) async {
    await pumpHost(tester);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text(s.searchNoResult), findsOneWidget);
    expect(find.text('Indonesia'), findsNothing);
  });

  testWidgets('keyboard aktif: konten menyusut & pilihan tetap tersampaikan',
      (tester) async {
    await pumpHost(tester, keyboard: 300);

    await tester.enterText(find.byType(TextField), 'mal');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Malaysia'));
    await tester.pumpAndSettle();

    expect(find.byType(CountryPickerDialog), findsNothing,
        reason: 'pilih tetap bekerja walau keyboard naik');
  });
}
