import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/widgets/chat_ui_shared.dart';
import 'package:chatyuk/widgets/empty_state_view.dart';

import 'test_helper.dart';

void main() {
  final s = S(isId: true);

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
      await tester.pumpWidget(wrap(EmptyStateView(
        icon: Icons.chat_bubble_outline,
        title: s.noPrivateChats,
        hint: s.emptyTimeline,
      )));
      expect(find.text(s.noPrivateChats), findsOneWidget);
      expect(find.text(s.emptyTimeline), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    });

    testWidgets('tanpa actionLabel = tanpa tombol', (tester) async {
      await tester.pumpWidget(wrap(EmptyStateView(
        icon: Icons.chat_bubble_outline,
        title: s.loading,
        hint: s.loading,
      )));
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('tap aksi memanggil onAction', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(EmptyStateView(
        icon: Icons.chat_bubble_outline,
        title: s.loading,
        hint: s.loading,
        actionLabel: s.btnRetry,
        onAction: () => tapped = true,
      )));
      await tester.tap(find.text(s.btnRetry));
      expect(tapped, isTrue);
    });
  });

  group('ChatIconButton', () {
    testWidgets('tap memanggil onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(wrap(ChatIconButton(
        open: false,
        onTap: () => tapped = true,
        tooltip: s.btnSave,
      )));
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      await tester.tap(find.byType(ChatIconButton));
      expect(tapped, isTrue);
    });

    testWidgets('open=true tampilkan ikon tutup', (tester) async {
      await tester.pumpWidget(wrap(ChatIconButton(
        open: true,
        onTap: () {},
        tooltip: s.btnClose,
      )));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
    });

    testWidgets('icon custom dipakai apa adanya', (tester) async {
      await tester.pumpWidget(wrap(ChatIconButton(
        icon: Icons.photo_camera_outlined,
        open: false,
        onTap: () {},
        tooltip: s.btnSave,
      )));
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
    });
  });
}
