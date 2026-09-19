import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/private_chat_message.dart';

/// REGRESSION (docs/FEATURE_MAP.md §3b):
/// 1. `SwipeToReply` WAJIB publik — sempat ditulis `_SwipeToReply` (privat)
///    sehingga gagal dipakai dari `room_chat_screen.dart`.
/// 2. `enabled=false` WAJIB mengembalikan `child` apa adanya (tanpa `Stack`)
///    — monitor admin read-only tidak boleh menanggung biaya layout.
/// 3. Ambang lepas 48 px: >=48 memicu, <48 batal.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: SizedBox(
          width: 300,
          height: 120,
          child: child,
        ))),
      );

  testWidgets('SwipeToReply publik & bisa dipakai lintas file', (tester) async {
    // Kalau kelas privat, referensi ini gagal compile — itulah gunanya test.
    await tester.pumpWidget(wrap(SwipeToReply(
      enabled: false,
      child: const Text('isi'),
    )));
    expect(find.byType(SwipeToReply), findsOneWidget);
  });

  testWidgets('enabled=false → child tampil apa adanya (tanpa Stack gesture)',
      (tester) async {
    await tester.pumpWidget(wrap(SwipeToReply(
      enabled: false,
      onReply: () {},
      child: const Text('read-only'),
    )));

    expect(find.text('read-only'), findsOneWidget);
    // Tanpa Stack pembungkus DARI SwipeToReply (scoped, bukan Scaffold).
    expect(
      find.descendant(
        of: find.byType(SwipeToReply),
        matching: find.byType(Stack),
      ),
      findsNothing,
    );
  });

  testWidgets('enabled=true → ada Stack + gesture horizontal', (tester) async {
    await tester.pumpWidget(wrap(SwipeToReply(
      enabled: true,
      onReply: () {},
      child: const Text('aktif'),
    )));

    expect(
      find.descendant(
        of: find.byType(SwipeToReply),
        matching: find.byType(Stack),
      ),
      findsOneWidget,
    );
  });

  testWidgets('drag >=48px → onReply dipanggil', (tester) async {
    var replied = 0;
    await tester.pumpWidget(wrap(SwipeToReply(
      enabled: true,
      onReply: () => replied++,
      child: const SizedBox(width: 200, height: 60),
    )));

    await tester.drag(find.byType(SwipeToReply), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(replied, 1);
  });

  testWidgets('drag <48px → onReply TIDAK dipanggil', (tester) async {
    var replied = 0;
    await tester.pumpWidget(wrap(SwipeToReply(
      enabled: true,
      onReply: () => replied++,
      child: const SizedBox(width: 200, height: 60),
    )));

    await tester.drag(find.byType(SwipeToReply), const Offset(20, 0));
    await tester.pumpAndSettle();
    expect(replied, 0);
  });

  testWidgets('drag ke kiri tidak memicu (hanya kanan)', (tester) async {
    var replied = 0;
    await tester.pumpWidget(wrap(SwipeToReply(
      enabled: true,
      onReply: () => replied++,
      child: const SizedBox(width: 200, height: 60),
    )));

    await tester.drag(find.byType(SwipeToReply), const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(replied, 0);
  });
}
