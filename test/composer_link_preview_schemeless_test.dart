import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/core/media/link_preview_service.dart';
import 'package:chatyuk/widgets/composer_link_preview.dart';
import 'package:chatyuk/widgets/link_preview.dart';

/// Regresi: kartu preview di ATAS KOLOM KETIK muncul juga untuk link
/// copy-paste TANPA `https://` (gerbang lama wajib memuat `http` → tak muncul).
void main() {
  Future<void> pumpComposer(WidgetTester tester, TextEditingController c) {
    return tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: ComposerLinkPreview(controller: c)),
        ),
      ),
    );
  }

  setUp(() {
    LinkPreviewService.instance.resetForTest();
    LinkPreviewService.instance.seedForTest(
      'https://youtube.com/shorts/abc',
      const LinkPreviewData(
        url: 'https://youtube.com/shorts/abc',
        title: 'Video pilihan',
        siteName: 'YouTube',
      ),
    );
    LinkPreviewService.instance.seedForTest(
      'https://tokopedia.com/a',
      const LinkPreviewData(
        url: 'https://tokopedia.com/a',
        title: 'Produk',
        siteName: 'Tokopedia',
      ),
    );
  });

  testWidgets('link tanpa skema → kartu muncul', (tester) async {
    final c = TextEditingController(text: 'youtube.com/shorts/abc');
    await pumpComposer(tester, c);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LinkPreview), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('https tetap muncul', (tester) async {
    final c = TextEditingController(text: 'cek https://tokopedia.com/a ya');
    await pumpComposer(tester, c);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LinkPreview), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('kalimat biasa (pakai spasi) TIDAK memicu kartu', (tester) async {
    final c = TextEditingController(text: 'halo. apa kabar hari ini');
    await pumpComposer(tester, c);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LinkPreview), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
