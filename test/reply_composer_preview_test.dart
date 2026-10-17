import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/widgets/reply_composer_preview.dart';

MessageModel _msg({String type = 'text', String text = 'halo', String img = ''}) =>
    MessageModel(
      id: 'm1',
      senderId: 'u1',
      senderName: 'Budi',
      senderGender: 'male',
      isRegistered: true,
      text: text,
      type: type,
      imageData: img,
      timestamp: DateTime(2026, 10, 17, 12),
    );

Future<void> _pump(WidgetTester t, MessageModel m, {VoidCallback? onCancel}) {
  return t.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReplyComposerPreview(
          message: m,
          senderLabel: 'Budi',
          s: S(isId: false),
          onCancel: onCancel ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('kartu solid (bukan transparan) + nama + teks', (t) async {
    await _pump(t, _msg());
    expect(find.text('Budi'), findsOneWidget);
    expect(find.text('halo'), findsOneWidget);
    final box = t.widget<Container>(
      find.descendant(
        of: find.byType(ReplyComposerPreview),
        matching: find.byType(Container),
      ).at(0),
    );
    final deco = box.decoration as BoxDecoration;
    expect(deco.color, AppTheme.bgCard);
  });

  testWidgets('foto tanpa caption tampil label Photo + ikon', (t) async {
    await _pump(t, _msg(type: 'image', text: '', img: 'x'));
    expect(find.text('[Photo]'), findsOneWidget);
    expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
  });

  testWidgets('tombol tutup memanggil onCancel', (t) async {
    var n = 0;
    await _pump(t, _msg(), onCancel: () => n++);
    await t.tap(find.byIcon(Icons.close));
    expect(n, 1);
  });
}
