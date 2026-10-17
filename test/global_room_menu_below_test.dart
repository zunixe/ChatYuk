import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/screens/online_users/widgets/global_room_nav.dart';

/// Mengunci helper ASLI yang dipakai ikon Global Room di halaman Online:
/// back dari chat room → MENU GLOBAL ROOM; back lagi → Online.
void main() {
  Widget page(String t) => Scaffold(appBar: AppBar(title: Text(t)));

  Future<void> open(WidgetTester t) async {
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: const Text('ONLINE')),
          body: TextButton(
            onPressed: () => openRoomWithMenuBelow(
              Navigator.of(ctx),
              menu: (_) => page('MENU GLOBAL ROOM'),
              room: (_) => page('ROOM'),
            ),
            child: const Text('ikon global room'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('ikon global room'));
    await t.pumpAndSettle();
  }

  testWidgets('ikon → langsung chat room (menu di bawahnya)', (t) async {
    await open(t);
    expect(find.text('ROOM'), findsOneWidget);
  });

  testWidgets('back dari room → menu Global Room, back lagi → Online', (t) async {
    await open(t);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('MENU GLOBAL ROOM'), findsOneWidget);
    expect(find.text('ROOM'), findsNothing);
    await t.pageBack();
    await t.pumpAndSettle();
    expect(find.text('ONLINE'), findsOneWidget);
  });
}
