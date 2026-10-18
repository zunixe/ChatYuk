import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/message/stretch_to_widest_column.dart';

/// Kutipan balasan selebar bubble: lebar kolom = anak terlebar, semua anak
/// dibentang selebar itu — tanpa intrinsic (aman untuk LayoutBuilder).
void main() {
  testWidgets('lebar = anak terlebar; anak sempit dibentang; LayoutBuilder aman', (t) async {
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: StretchToWidestColumn(children: [
            const SizedBox(key: ValueKey('narrow'), width: 80, height: 10),
            const SizedBox(key: ValueKey('wide'), width: 200, height: 20),
            LayoutBuilder(builder: (_, c) => SizedBox(key: const ValueKey('lb'), width: 50, height: 5)),
          ]),
        ),
      ),
    ));
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(StretchToWidestColumn)), const Size(200, 35));
    expect(t.getSize(find.byKey(const ValueKey('narrow'))).width, 200);
    expect(t.getTopLeft(find.byKey(const ValueKey('wide'))).dy, 10);
  });

  testWidgets('anak lebih lebar dari batas → dipotong ke batas', (t) async {
    await t.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 120,
          child: StretchToWidestColumn(children: [SizedBox(width: 500, height: 10)]),
        ),
      ),
    ));
    expect(t.getSize(find.byType(StretchToWidestColumn)).width, 120);
  });
}
