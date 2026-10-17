import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/chat_info_snack.dart';

/// Regresi: SnackBar chat (termasuk yang ber-ACTION/UNDO) WAJIB hilang
/// otomatis. Flutter 3.4x: `persist = persist ?? action != null` →
/// tanpa `persist: false`, snackbar ber-action TIDAK pernah hilang.
void main() {
  Future<void> pumpAndDismiss(WidgetTester t, {required bool withAction}) async {
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => showChatSnack(
                ctx,
                'TES',
                action: withAction
                    ? SnackBarAction(label: 'Undo', onPressed: () {})
                    : null,
              ),
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('go'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 400)); // animasi show
    await t.pump(const Duration(seconds: 4)); // durasi
    await t.pump(const Duration(milliseconds: 400)); // animasi hide
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('TES'), findsNothing);
  }

  testWidgets('snackbar chat TANPA action → hilang otomatis', (t) async {
    await pumpAndDismiss(t, withAction: false);
  });

  testWidgets('snackbar chat DENGAN action (UNDO) → tetap hilang otomatis',
      (t) async {
    await pumpAndDismiss(t, withAction: true);
  });

  testWidgets('persist=false eksplisit di SnackBar', (t) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (ctx) => ElevatedButton(
        onPressed: () => showChatSnack(ctx, 'X',
            action: SnackBarAction(label: 'U', onPressed: () {})),
        child: const Text('go')))),
    ));
    await t.tap(find.text('go'));
    await t.pump();
    expect(t.widget<SnackBar>(find.byType(SnackBar)).persist, isFalse);
    await t.pump(const Duration(seconds: 4));
    await t.pump(const Duration(milliseconds: 400));
  });
}
