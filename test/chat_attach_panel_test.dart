import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/widgets/chat_ui_shared.dart';

void main() {
  testWidgets('panel lampiran: latar solid, grid 4 kolom, tap berfungsi', (
    t,
  ) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 800);
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });
    var taps = 0;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatAttachPanel(
            children: [
              for (var i = 0; i < 5; i++)
                ChatAttachChip(
                  icon: Icons.image_rounded,
                  color: Colors.blue,
                  label: 'Item $i',
                  onTap: () => taps++,
                ),
            ],
          ),
        ),
      ),
    );
    final panel = t.widget<Container>(find.byType(Container).first);
    expect((panel.decoration as BoxDecoration).color, AppTheme.bgCard);
    // 4 per baris → item ke-0 dan ke-4 beda baris, item 0..3 sejajar.
    final y = [
      for (var i = 0; i < 5; i++) t.getTopLeft(find.text('Item $i')).dy,
    ];
    expect(y[0], y[3]);
    expect(y[4], greaterThan(y[0]));
    await t.tap(find.text('Item 2'));
    expect(taps, 1);
  });
}
