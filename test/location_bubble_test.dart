import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/core/chat/chat_location.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/widgets/location_bubble.dart';

/// Regresi: bubble chat memakai LocationBubble non-interaktif
/// (InteractiveFlag.none). Kalau mode ini gagal render (map hilang di
/// bubble walau preview composer tampil), test ini merah.
void main() {
  Widget host(LocationBubble b) => ChangeNotifierProvider(
    create: (_) => LocaleProvider(),
    child: MaterialApp(home: Scaffold(body: Center(child: b))),
  );

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
}
