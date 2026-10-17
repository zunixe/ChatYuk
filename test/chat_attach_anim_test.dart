import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresi ANIMASI PANEL LAMPIRAN (menu "+"):
///  - BUKA  : panel naik dari bawah, composer terdorong naik mulus.
///  - TUTUP : panel TURUN ke bawah DAN composer ikut turun BERSAMAAN
///            (tidak ada fase "isi sudah hilang tapi ruang masih ada").
///
/// Bug lama: `AnimatedSize` + `AnimatedSwitcher` → saat menutup switcher
/// menumpuk child lama & baru sehingga tinggi diukur MAKSIMUM; posisi composer
/// tidak bergerak selama animasi lalu ruang kosong lenyap mendadak (terasa
/// tersendat / "kurang mulus dari halaman chat ke bawah").
///
/// Widget `_AttachPanelSlide` di bawah adalah salinan perilaku yang dipakai
/// `chat_composer_input.dart` (satu controller untuk tinggi+slide+fade).
class _AttachPanelSlide extends StatefulWidget {
  final bool open;
  final Widget child;
  const _AttachPanelSlide({required this.open, required this.child});

  @override
  State<_AttachPanelSlide> createState() => _AttachPanelSlideState();
}

class _AttachPanelSlideState extends State<_AttachPanelSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  @override
  void initState() {
    super.initState();
    if (widget.open) _c.value = 1;
  }

  @override
  void didUpdateWidget(_AttachPanelSlide old) {
    super.didUpdateWidget(old);
    if (widget.open == old.open) return;
    widget.open ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _a,
    builder: (c, child) {
      final t = _a.value;
      if (t == 0) return const SizedBox.shrink();
      return ClipRect(
        child: Align(
          alignment: Alignment.bottomCenter,
          heightFactor: t,
          child: Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: FractionalTranslation(
              translation: Offset(0, 0.35 * (1 - t)),
              child: child,
            ),
          ),
        ),
      );
    },
    child: widget.child,
  );
}

void main() {
  Widget harness({required bool open}) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          const Spacer(),
          // "Composer" — posisinya jadi patokan apakah tinggi ikut menyusut.
          Container(
            key: const ValueKey('composer'),
            height: 50,
            color: Colors.blueGrey,
          ),
          _AttachPanelSlide(
            open: open,
            child: const SizedBox(
              height: 120,
              width: double.infinity,
              child: Text('PANEL'),
            ),
          ),
        ],
      ),
    ),
  );

  testWidgets('BUKA: panel naik dari bawah', (t) async {
    await t.pumpWidget(harness(open: false));
    await t.pumpAndSettle();
    expect(find.text('PANEL'), findsNothing);

    await t.pumpWidget(harness(open: true));
    await t.pump(const Duration(milliseconds: 30));
    final early = t.getTopLeft(find.text('PANEL')).dy;

    await t.pumpAndSettle();
    final settled = t.getTopLeft(find.text('PANEL')).dy;
    expect(early, greaterThan(settled), reason: 'panel harus naik dari bawah');
  });

  testWidgets('TUTUP: panel turun ke bawah', (t) async {
    await t.pumpWidget(harness(open: true));
    await t.pumpAndSettle();
    final settled = t.getTopLeft(find.text('PANEL')).dy;

    await t.pumpWidget(harness(open: false));
    await t.pump(const Duration(milliseconds: 100));
    expect(
      t.getTopLeft(find.text('PANEL')).dy,
      greaterThan(settled),
      reason: 'panel harus TURUN saat menutup',
    );

    await t.pumpAndSettle();
    expect(find.text('PANEL'), findsNothing);
  });

  testWidgets('TUTUP: composer ikut turun BERSAMAAN (tinggi menyusut)', (
    t,
  ) async {
    await t.pumpWidget(harness(open: true));
    await t.pumpAndSettle();
    final composerOpen = t
        .getTopLeft(find.byKey(const ValueKey('composer')))
        .dy;

    await t.pumpWidget(harness(open: false));
    await t.pump(const Duration(milliseconds: 100)); // tengah animasi
    final composerMid = t
        .getTopLeft(find.byKey(const ValueKey('composer')))
        .dy;

    await t.pumpAndSettle();
    final composerClosed = t
        .getTopLeft(find.byKey(const ValueKey('composer')))
        .dy;

    // Composer bergerak turun (> posisi terbuka) SAAT animasi berjalan.
    expect(
      composerMid,
      greaterThan(composerOpen),
      reason: 'composer harus bergerak turun selama animasi tutup, '
          'bukan diam lalu melompat. open=$composerOpen mid=$composerMid',
    );
    // Dan sudah sampai posisi akhirnya.
    expect(composerClosed, greaterThan(composerMid));
  });

  testWidgets('TUTUP selesai ~200ms (tidak menggantung)', (t) async {
    await t.pumpWidget(harness(open: true));
    await t.pumpAndSettle();

    await t.pumpWidget(harness(open: false));
    await t.pump(const Duration(milliseconds: 210));
    await t.pump();
    expect(find.text('PANEL'), findsNothing);
  });

  testWidgets('buka-tutup berulang tetap konsisten', (t) async {
    await t.pumpWidget(harness(open: false));
    await t.pumpAndSettle();
    final closedY = t
        .getTopLeft(find.byKey(const ValueKey('composer')))
        .dy;

    for (var i = 0; i < 3; i++) {
      await t.pumpWidget(harness(open: true));
      await t.pumpAndSettle();
      expect(find.text('PANEL'), findsOneWidget);
      await t.pumpWidget(harness(open: false));
      await t.pumpAndSettle();
      expect(find.text('PANEL'), findsNothing);
      expect(
        t.getTopLeft(find.byKey(const ValueKey('composer'))).dy,
        closeTo(closedY, 0.01),
      );
    }
  });
}
