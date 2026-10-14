import 'package:chatyuk/widgets/message/code_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    );

void main() {
  group('splitCodeSegments', () {
    test('teks tanpa pagar → satu segmen teks', () {
      final segs = splitCodeSegments('halo dunia');
      expect(segs.length, 1);
      expect(segs.first.isCode, isFalse);
      expect(segs.first.content, 'halo dunia');
    });

    test('blok kode dengan bahasa terdeteksi', () {
      final segs = splitCodeSegments('sebelum\n```dart\nvoid main() {}\n```\n');
      final code = segs.where((s) => s.isCode).toList();
      expect(code.length, 1);
      expect(code.first.lang, 'dart');
      expect(code.first.content, 'void main() {}');
    });
  });

  group('codeHighlightSpansMemo', () {
    test('hasil identik & cache dipakai ulang (instance sama)', () {
      const code = 'def foo():\n  return 1\n';
      final a = codeHighlightSpansMemo(code, 'python');
      final b = codeHighlightSpansMemo(code, 'python');
      // Memo → list spans yang sama (tidak tokenize ulang).
      expect(identical(a, b), isTrue);
      expect(a, isNotEmpty);
    });

    test('kunci berbeda saat bahasa berbeda', () {
      const code = 'x = 1';
      final a = codeHighlightSpansMemo(code, 'python');
      final b = codeHighlightSpansMemo(code, 'sql');
      expect(identical(a, b), isFalse);
    });
  });

  group('CodeBlock compact', () {
    testWidgets('blok pendek: tak ada tombol tampilkan semua', (tester) async {
      await tester.pumpWidget(
        _wrap(const CodeBlock(code: 'a\nb\nc', language: 'txt', maxLines: 10)),
      );
      expect(find.textContaining('Tampilkan'), findsNothing);
      expect(find.textContaining('Show'), findsNothing);
    });

    testWidgets('blok panjang: tombol tampilkan semua muncul & memperluas',
        (tester) async {
      final longCode = List.generate(100, (i) => 'line$i').join('\n');
      await tester.pumpWidget(
        _wrap(CodeBlock(code: longCode, language: 'txt', maxLines: 10)),
      );
      // Label tombol = "Tampilkan 90 baris lagi" (100 - 10).
      final moreBtn = find.textContaining('Tampilkan 90');
      expect(moreBtn, findsOneWidget);
      // Ketuk → tombol hilang (diperluas penuh).
      await tester.tap(moreBtn);
      await tester.pumpAndSettle();
      expect(find.textContaining('Tampilkan 90'), findsNothing);
    });
  });
}
