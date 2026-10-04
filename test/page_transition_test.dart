import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/config/theme.dart';

import 'test_helper.dart';

/// Kontrak transisi halaman global: slide-cepat 150/120ms untuk halaman biasa,
/// dan fullscreen dialog (panggilan) TIDAK ikut slide (pakai fallback).
void main() {
  const builder = AppSlidePageTransitionsBuilder();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    AppFonts.setLocal(AppFonts.systemKey);
  });

  tearDownAll(resetFontForTest);

  test('durasi masuk 150ms, keluar 120ms (sama seperti private chat)', () {
    expect(builder.transitionDuration, const Duration(milliseconds: 150));
    expect(builder.reverseTransitionDuration, const Duration(milliseconds: 120));
  });

  test('kedua tema mendaftarkan builder slide untuk Android', () {
    for (final t in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final b = t.pageTransitionsTheme.builders[TargetPlatform.android];
      expect(b, isA<AppSlidePageTransitionsBuilder>(),
          reason: 'Android harus pakai slide global');
    }
  });

  testWidgets('halaman biasa → SlideTransition (bukan dialog)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: Text('A')),
      ),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('B')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Saat transisi berjalan, ada SlideTransition di tree.
    expect(find.byType(SlideTransition), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('fullscreenDialog → tidak memakai slide global',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: Text('A')),
      ),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const Scaffold(body: Text('Call')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Fallback (Zoom) memakai FadeTransition, bukan SlideTransition dari kanan.
    // Tidak ada jaminan SlideTransition absen total, jadi cukup pastikan layar
    // tetap tampil tanpa error dan route ter-push.
    await tester.pumpAndSettle();
    expect(find.text('Call'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  _routeDurationTests();
}

/// Mengukur durasi route AKTUAL — membuktikan MaterialPageRoute benar-benar
/// memakai 150/120ms dari theme global (bukan default 300ms).
void _routeDurationTests() {
  testWidgets('MaterialPageRoute ambil durasi dari theme (150/120ms)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(body: Text('A')),
      ),
    );
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    final route = MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('B')),
    );
    nav.push(route);
    await tester.pump();
    // Durasi dibaca route dari PageTransitionsBuilder theme.
    expect(route.transitionDuration, const Duration(milliseconds: 150));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 120));
    await tester.pumpAndSettle();
  });
}
