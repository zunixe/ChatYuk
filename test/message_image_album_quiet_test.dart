import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/message/message_image.dart';

import 'test_helper.dart';

/// Mengunci: tile ALBUM (fill:true) = placeholder SENYAP (tanpa spinner),
/// sedangkan foto biasa tetap memakai spinner saat memuat.
void main() {
  final pngB64 = base64Encode(base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
  ));

  setUp(mockPathProvider);

  Future<void> pumpTile(WidgetTester t, {required bool fill}) async {
    await t.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 120,
                child: MessageImage(
                  imageData: pngB64,
                  chatKey: 'private_test',
                  messageId: 'm-$fill',
                  fill: fill,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pump(); // frame pertama (masih memuat)
  }

  testWidgets('tile album → TANPA spinner (placeholder senyap)',
      (tester) async {
    await pumpTile(tester, fill: true);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('foto biasa → spinner DITUNDA (tak ada kilatan di frame awal)',
      (tester) async {
    await pumpTile(tester, fill: false);
    // Spinner ditunda 250ms: load cepat (cache/disk) selesai dulu → tidak
    // ada kilatan spinner beranimasi = anti "kedip".
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('TIDAK ada fade/Opacity animasi (foto muncul utuh)',
      (tester) async {
    await pumpTile(tester, fill: false);
    // Fade 180ms dihapus → tidak boleh ada TweenAnimationBuilder pembungkus.
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    await tester.pump(const Duration(seconds: 2));
  });
}
