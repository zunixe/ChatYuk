import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/widgets/message_reaction_bar.dart';

/// Functional: bar reaksi emoji nyata — tap emoji memanggil `onReact`
/// dengan emoji yang benar; tombol "more" (⋯) memanggil `onMore`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          backgroundColor: AppTheme.bgScreen,
          body: Center(child: child),
        ),
      );

  testWidgets('tap emoji pertama → onReact(emoji) tepat', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(wrap(ReactionBar(onReact: tapped.add)));

    await tester.tap(find.text('👍'));
    await tester.pump();

    expect(tapped, ['👍']);
  });

  testWidgets('tap dua emoji berbeda → urutan benar', (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(wrap(ReactionBar(onReact: tapped.add)));

    await tester.tap(find.text('❤️'));
    await tester.pump();
    await tester.tap(find.text('😂'));
    await tester.pump();

    expect(tapped, ['❤️', '😂']);
  });

  testWidgets('semua emoji cepat bisa ditap (tidak ada yang mati)',
      (tester) async {
    final tapped = <String>[];
    await tester.pumpWidget(wrap(ReactionBar(onReact: tapped.add)));

    for (final e in kQuickReactions) {
      await tester.tap(find.text(e));
      await tester.pump();
    }
    expect(tapped.length, kQuickReactions.length);
  });

  testWidgets('tap ⋯ → onMore terpanggil', (tester) async {
    var more = 0;
    await tester.pumpWidget(wrap(ReactionBar(
      onReact: (_) {},
      onMore: () => more++,
    )));

    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(more, 1);
  });
}
