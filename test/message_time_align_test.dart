import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/message/message_text_with_time.dart';

/// Jam bubble BALASAN harus rata kanan bubble (teks tetap kiri).
Widget _wrap(Widget child, {double width = 300}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  testWidgets('fillWidth: jam menempel tepi KANAN, teks tetap kiri', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const MessageTextWithTime(
          text: 'halo',
          timeStr: '10:11',
          textStyle: TextStyle(fontSize: 16),
          timeStyle: TextStyle(fontSize: 11),
          alignRight: false,
          fillWidth: true,
        ),
      ),
    );
    final timeRight = tester.getTopRight(find.text('10:11')).dx;
    const boxWidth = 300.0;
    // Jam menempel tepi KANAN bubble.
    expect(timeRight, greaterThan(boxWidth - 4));
  });

  testWidgets('tanpa fillWidth: jam ikut teks (perilaku lama)', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const MessageTextWithTime(
          text: 'halo',
          timeStr: '10:11',
          textStyle: TextStyle(fontSize: 16),
          timeStyle: TextStyle(fontSize: 11),
          alignRight: false,
        ),
      ),
    );
    final timeRight = tester.getTopRight(find.text('10:11')).dx;
    // Tidak menempel tepi kanan 300 → tetap dekat teks.
    expect(timeRight, lessThan(150));
  });
  testWidgets('fillWidth + alignRight: teks tetap KIRI, jam KANAN', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const MessageTextWithTime(
          text: 'halo dunia panjang sekali ya',
          timeStr: '10:11',
          textStyle: TextStyle(fontSize: 16),
          timeStyle: TextStyle(fontSize: 11),
          alignRight: true,
          fillWidth: true,
        ),
      ),
    );
    final jam = tester.getTopLeft(find.text('10:11')).dx;
    expect(jam, greaterThan(200), reason: 'jam harus di kanan');
  });
}
