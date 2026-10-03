import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/config/strings_docs.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/theme_provider.dart';
import 'package:chatyuk/screens/admin_docs_tab.dart';

import 'test_helper.dart';

/// Widget hermetic `AdminDocsTab`: tab Dokumentasi menampilkan dua sub-tab
/// (Pengguna + Developer), semua teks lewat `s.` (bilingual), dan kolom
/// cari memfilter kartu dokumentasi.
void main() {
  final s = S(isId: true);

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    AppFonts.setLocal(AppFonts.systemKey);
    await initSupabaseForTest();
  });

  tearDownAll(resetFontForTest);

  Widget wrap() => MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleProvider>(
            create: (_) => LocaleProvider(),
          ),
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: AdminDocsTab())),
      );

  testWidgets('mount → sub-tab Pengguna + Developer + kartu user tampil',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text(s.adminDocsUser), findsOneWidget);
    expect(find.text(s.adminDocsDeveloper), findsOneWidget);
    expect(find.text(s.docsUserAuthTitle), findsOneWidget);
    expect(find.text(s.docsUserPrivateTitle), findsOneWidget);
  });

  testWidgets('tap Developer → kartu arsitektur tampil', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(s.adminDocsDeveloper));
    await tester.pumpAndSettle();

    expect(find.text(s.docsDevLayersTitle), findsOneWidget);
    expect(find.text(s.docsDevServicesTitle), findsOneWidget);
  });

  testWidgets('cari memfilter kartu', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'voice stage');
    await tester.pumpAndSettle();

    // Kartu voice stage cocok; kartu auth tidak.
    expect(find.text(s.docsUserRoomLiveTitle), findsOneWidget);
    expect(find.text(s.docsUserAuthTitle), findsNothing);
  });

  testWidgets('kartu lengkap tampil (tidak hanya sebagian)',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // Beberapa kartu user kunci harus ada sekaligus.
    for (final t in [
      s.docsUserOrganizeTitle,
      s.docsUserPhotoPayTitle,
      s.docsUserCoinFxTitle,
      s.docsUserSocialTitle,
      s.docsUserDonateTitle,
    ]) {
      expect(find.text(t), findsOneWidget, reason: 'kartu hilang: $t');
    }

    // Developer: kartu baru (model, error, test, panel admin).
    await tester.tap(find.text(s.adminDocsDeveloper));
    await tester.pumpAndSettle();
    for (final t in [
      s.docsDevModelsTitle,
      s.docsDevErrorsTitle,
      s.docsDevTestsTitle,
      s.docsDevAdminPanelTitle,
    ]) {
      expect(find.text(t), findsOneWidget, reason: 'kartu hilang: $t');
    }
  });

  testWidgets('Developer: diagram alur tampil (5 buah)', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.adminDocsDeveloper));
    await tester.pumpAndSettle();

    expect(find.text(s.docsDevDiagramsTitle), findsOneWidget);
    for (final t in [
      s.docsDevLayerDiagramTitle,
      s.docsDevMessageFlowTitle,
      s.docsDevNotifFlowTitle,
      s.docsDevCallFlowTitle,
      s.docsDevCoinFlowTitle,
    ]) {
      expect(find.text(t), findsOneWidget, reason: 'diagram hilang: $t');
    }
    // Tombol salin diagram ada (per diagram).
    expect(find.byIcon(Icons.copy_rounded), findsNWidgets(5));
  });

  testWidgets('cari diagram pakai kata kunci arsitektur', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.adminDocsDeveloper));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'webrtc');
    await tester.pumpAndSettle();

    // Diagram call cocok; diagram koin tidak.
    expect(find.text(s.docsDevCallFlowTitle), findsOneWidget);
    expect(find.text(s.docsDevCoinFlowTitle), findsNothing);
  });
}
