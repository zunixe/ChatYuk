import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/chat/chat_location.dart';
import 'package:chatyuk/widgets/location_bubble.dart';

/// Regresi: bubble chat memakai LocationBubble non-interaktif
/// (InteractiveFlag.none). Kalau mode ini gagal render (map hilang di
/// bubble walau preview composer tampil), test ini merah.
void main() {
  Widget host(LocationBubble b) =>  ProviderScope(child: MaterialApp(home: Scaffold(body: Center(child: b))));

  testWidgets('LocationBubble non-interaktif render tanpa error', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const LocationBubble(
          location: ChatLocation(lat: -6.9, lng: 107.6),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LocationBubble), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LocationBubble interaktif (preview composer) render', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const LocationBubble(
          location: ChatLocation(lat: -6.9, lng: 107.6),
          width: double.infinity,
          height: 150,
          interactive: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LocationBubble), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'tap bubble non-interaktif MEMICU aksi (regresi FlutterMap serap gesture)',
    (tester) async {
      // Dulu FlutterMap menyerap pointer walau InteractiveFlag.none →
      // GestureDetector luar tak dapat tap → Maps tak pernah terbuka.
      var taps = 0;
      await tester.pumpWidget(
        host(
          LocationBubble(
            location: const ChatLocation(lat: -6.9, lng: 107.6),
            onTapOverride: () => taps++,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(LocationBubble));
      await tester.pump();
      expect(taps, 1, reason: 'tap harus sampai ke pembungkus');
    },
  );
}
