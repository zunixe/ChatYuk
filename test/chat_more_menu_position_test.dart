import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresi: menu titik-3 di header chat harus muncul DI SAMPING/BAWAH ikonnya,
/// bukan melayang jauh di tengah layar.
///
/// Default `PopupMenuButton` menaruh menu di TENGAH layar (overlay center).
/// Perbaikan: `position: PopupMenuPosition.under` + `offset` kecil.
void main() {
  Widget harness({
    required PopupMenuPosition position,
    Offset offset = Offset.zero,
  }) => MaterialApp(
    home: Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('more'),
            icon: const Icon(Icons.more_vert),
            position: position,
            offset: offset,
            onSelected: (_) {},
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'a', child: Text('Cari')),
              PopupMenuItem(value: 'b', child: Text('Blokir')),
            ],
          ),
        ],
      ),
      body: const SizedBox.expand(),
    ),
  );

  testWidgets('perbaikan: menu menempel di bawah ikon titik-3', (t) async {
    t.view.devicePixelRatio = 1.0;
    t.view.physicalSize = const Size(400, 800);
    addTearDown(() {
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
    });

    await t.pumpWidget(
      harness(
        position: PopupMenuPosition.under,
        offset: const Offset(-8, 4),
      ),
    );
    final iconRect = t.getRect(find.byKey(const ValueKey('more')));

    await t.tap(find.byKey(const ValueKey('more')));
    await t.pumpAndSettle();

    final menuRect = t.getRect(find.byType(PopupMenuItem<String>).first);
    final gap = menuRect.top - iconRect.bottom;

    // Menu tepat di bawah ikon: jarak kecil (offset 4px + padding), bukan
    // ratusan piksel seperti posisi default.
    expect(
      gap,
      lessThan(30),
      reason: 'menu harus menempel di bawah ikon, gap=$gap',
    );
    // Dan sejajar horizontal dengan ikon (bukan di tengah layar).
    expect(
      (menuRect.right - iconRect.right).abs(),
      lessThan(40),
      reason: 'tepi kanan menu harus dekat tepi kanan ikon',
    );
  });
}
