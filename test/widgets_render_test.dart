import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/screens/point_history/widgets/history_tile.dart';
import 'package:chatyuk/widgets/skeleton_card.dart';

/// Fase 5 — widget stateless murni: skeleton & history tile (render).
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('SkeletonCard / SkeletonList', () {
    testWidgets('SkeletonCard render tanpa error', (tester) async {
      await tester.pumpWidget(wrap(const SkeletonCard(height: 80)));
      expect(find.byType(SkeletonCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('SkeletonList menampilkan sebanyak count', (tester) async {
      await tester.pumpWidget(wrap(const SkeletonList(count: 4)));
      await tester.pump();
      expect(find.byType(SkeletonCard), findsNWidgets(4));
    });

    testWidgets('PostSkeletonCard render', (tester) async {
      await tester.pumpWidget(wrap(const PostSkeletonCard()));
      expect(find.byType(PostSkeletonCard), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PostSkeletonList render item (min 1, lazy list)', (tester) async {
      await tester.pumpWidget(wrap(const PostSkeletonList(count: 3)));
      await tester.pump();
      // ListView lazy → hanya yang visible yang ter-build.
      expect(find.byType(PostSkeletonCard), findsWidgets);
    });
  });

  group('HistoryTile', () {
    final s = S(isId: true);

    testWidgets('kredit (amount>0) → ikon + tanpa error', (tester) async {
      await tester.pumpWidget(wrap(Scaffold(
        body: HistoryTile(
          entry: {
            'amount': 100,
            'type': 'daily_login',
            'bucket': 'earned',
            'created_at': '2026-01-02T03:04:05Z',
          },
          s: s,
        ),
      )));
      expect(find.byType(ListTile), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('debit (amount<0) → ikon minus + tanpa error', (tester) async {
      await tester.pumpWidget(wrap(Scaffold(
        body: HistoryTile(
          entry: {
            'amount': -50,
            'type': 'spend_chat',
            'bucket': 'spent',
            'metadata': {'msg_type': 'image'},
            'created_at': '2026-01-02T03:04:05Z',
          },
          s: s,
        ),
      )));
      expect(find.byType(ListTile), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('entry minim (field hilang) tetap render tanpa crash',
        (tester) async {
      await tester.pumpWidget(wrap(Scaffold(
        body: HistoryTile(entry: const {}, s: s),
      )));
      expect(find.byType(ListTile), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('created_at tidak valid → pakai waktu sekarang, tidak crash',
        (tester) async {
      await tester.pumpWidget(wrap(Scaffold(
        body: HistoryTile(
          entry: {'amount': 5, 'created_at': 'bukan-tanggal'},
          s: s,
        ),
      )));
      expect(tester.takeException(), isNull);
    });
  });
}
