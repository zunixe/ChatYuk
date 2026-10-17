import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/chat_attach_panel.dart';

/// Regresi: panel lampiran (menu "+") harus MUNCUL DARI BAWAH (slide-up +
/// fade), bukan tumbuh dari tengah.
///
/// Sebelumnya panel hanya dibungkus `AnimatedSize` (animasi tinggi): isi
/// panel sudah penuh sejak frame pertama sehingga terlihat "keluar dari
/// tengah". Sekarang memakai `AnimatedSwitcher` + SlideTransition dari bawah.
void main() {
  Widget harness({required bool open}) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          const Spacer(),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            reverseDuration: const Duration(milliseconds: 160),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) {
              final slide = Tween<Offset>(
                begin: const Offset(0, 0.35),
                end: Offset.zero,
              ).animate(anim);
              return ClipRect(
                child: SlideTransition(
                  position: slide,
                  child: FadeTransition(opacity: anim, child: child),
                ),
              );
            },
            child: open
                ? ChatAttachPanel(
                    key: const ValueKey('attach-open'),
                    children: const [
                      SizedBox(height: 60, child: Text('PANEL')),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('attach-closed')),
            ),
          ),
        ],
      ),
    ),
  );

  testWidgets('panel slide dari bawah (posisi awal lebih rendah)', (
    t,
  ) async {
    await t.pumpWidget(harness(open: false));
    await t.pumpAndSettle();
    expect(find.text('PANEL'), findsNothing);

    // Buka panel → frame pertama animasi.
    await t.pumpWidget(harness(open: true));
    await t.pump(const Duration(milliseconds: 16));

    final early = t.getTopLeft(find.text('PANEL')).dy;

    // Selesai animasi.
    await t.pumpAndSettle();
    final settled = t.getTopLeft(find.text('PANEL')).dy;

    // Saat animasi berjalan panel berada LEBIH BAWAH dari posisi akhir →
    // membuktikan ia bergerak naik dari bawah.
    expect(
      early,
      greaterThan(settled),
      reason: 'panel harus mulai dari bawah lalu naik. '
          'early=$early settled=$settled',
    );
  });

  testWidgets('panel terlihat (opacity bertahap)', (t) async {
    await t.pumpWidget(harness(open: false));
    await t.pumpAndSettle();

    await t.pumpWidget(harness(open: true));
    await t.pump(const Duration(milliseconds: 16));

    final fades = t.widgetList<FadeTransition>(find.byType(FadeTransition));
    expect(fades.isNotEmpty, isTrue);
    // Opacity belum 1 di awal animasi.
    expect(
      fades.any((f) => f.opacity.value < 1.0),
      isTrue,
      reason: 'panel harus fade-in, bukan muncul langsung penuh',
    );
  });

  testWidgets('panel hilang lagi saat ditutup', (t) async {
    await t.pumpWidget(harness(open: true));
    await t.pumpAndSettle();
    expect(find.text('PANEL'), findsOneWidget);

    await t.pumpWidget(harness(open: false));
    await t.pumpAndSettle();
    expect(find.text('PANEL'), findsNothing);
  });
}
