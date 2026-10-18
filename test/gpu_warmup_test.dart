import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/gpu_warmup.dart';

/// Pemanasan pipeline GPU: muncul ±2 dtk setelah frame pertama, digambar
/// beberapa frame (2×2 px, tak bisa disentuh), lalu HILANG — sekali saja.
void main() {
  testWidgets('warm-up tampil sementara lalu lepas, sekali per proses', (t) async {
    Widget app() => const MaterialApp(
      home: Scaffold(body: Stack(children: [SizedBox.expand(), GpuWarmup()])),
    );
    await t.pumpWidget(app());
    expect(find.byType(ShaderMask), findsNothing, reason: 'belum mulai');
    await t.pump(const Duration(seconds: 2));
    await t.pump();
    expect(find.byType(ShaderMask), findsOneWidget, reason: 'efek digambar');
    expect(t.getSize(find.byType(RepaintBoundary).last), const Size(2, 2));
    for (var i = 0; i < GpuWarmup.frames + 2; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(ShaderMask), findsNothing, reason: 'sudah dilepas');
    // Mount ulang (mis. rebuild root) → tidak memanaskan lagi.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(app());
    await t.pump(const Duration(seconds: 3));
    expect(find.byType(ShaderMask), findsNothing);
  });
}
