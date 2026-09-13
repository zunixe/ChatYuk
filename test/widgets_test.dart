import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/widgets/chat_ui_shared.dart';
import 'package:chatyuk/widgets/empty_state_view.dart';

import 'test_helper.dart';

/// Smoke test widget bersama: render tanpa throw, tap jalan.
void main() {
  setUpAll(() async {
    await initSupabaseForTest();
  });

  Widget wrap(Widget child) => MaterialApp(
        home: ChangeNotifierProvider<LocaleProvider>(
          create: (_) => LocaleProvider(),
          child: Scaffold(body: child),
        ),
      );

  group('EmptyStateView', () {
    testWidgets('tampilkan ikon + judul + hint', (tester) async {
      await tester.pumpWidget(wrap(const EmptyStateView(
        icon: Icons.chat_bubble_outline,
        title: 'Belum ada chat',
        hint: 'Mulai dari tab online',
      )));
      expect(find.text('Belum ada chat'), findsOneWidget);
      expect(find.text('Mulai dari tab online'), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });

    testWidgets('tanpa actionLabel = tanpa tombol', (tester) async {
      await tester.pumpWidget(wrap(const EmptyStateView(
        icon: Icons.chat_bubble_outline,
        title: 'T',
        hint: 'H',
      )));
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('tap aksi memanggil onAction', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(EmptyStateView(
        icon: Icons.chat_bubble_outline,
        title: 'T',
        hint: 'H',
        actionLabel: 'Buat',
        onAction: () => tapped = true,
      )));
      await tester.tap(find.text('Buat'));
      expect(tapped, isTrue);
    });
  });

  group('ChatIconButton', () {
    testWidgets('tap memanggil onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(ChatIconButton(
        open: false,
        onTap: () => tapped = true,
        tooltip: 'lampirkan',
      )));
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      await tester.tap(find.byType(ChatIconButton));
      expect(tapped, isTrue);
    });

    testWidgets('open=true tampilkan ikon tutup', (tester) async {
      await tester.pumpWidget(wrap(ChatIconButton(
        open: true,
        onTap: () {},
        tooltip: 'tutup',
      )));
      // Tunggu animasi rotasi selesai agar ikon final ter-render.
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
    });

    testWidgets('icon custom dipakai apa adanya', (tester) async {
      await tester.pumpWidget(wrap(ChatIconButton(
        icon: Icons.photo_camera_outlined,
        open: false,
        onTap: () {},
        tooltip: 'foto',
      )));
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    });
  });
}
