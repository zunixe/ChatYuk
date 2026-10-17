import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/chat_ui_shared.dart';

/// Regresi tampilan tombol "+" composer: saat diklik ikon berubah menjadi ✕
/// dengan UKURAN SAMA (bukan dua glif beda besar). Dulu tombol memakai
/// `add_circle_outline` → `close`: lingkaran penuh 20px lalu ✕ kecil di
/// dalamnya, sehingga terlihat "kebesaran" setelah diklik.
void main() {
  Future<void> pump(WidgetTester t, {required bool open}) {
    return t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ChatIconButton(
              icon: open ? Icons.close_rounded : Icons.add_rounded,
              open: open,
              onTap: () {},
              tooltip: 'lampiran',
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('ikon + dan ✕ memakai ukuran yang sama (18px)', (t) async {
    await pump(t, open: false);
    final plus = t.widget<Icon>(find.byType(Icon));
    expect(plus.icon, Icons.add_rounded);
    expect(plus.size, 18.0);
    final plusSize = t.getSize(find.byType(Icon));

    await pump(t, open: true);
    final close = t.widget<Icon>(find.byType(Icon));
    expect(close.icon, Icons.close_rounded);
    expect(close.size, 18.0);
    final closeSize = t.getSize(find.byType(Icon));

    // Ukuran render kotak ikon identik → tidak ada lompatan "membesar".
    expect(closeSize, plusSize);
  });

  testWidgets('lingkaran latar tetap 30px & ikon muat proporsional', (t) async {
    await pump(t, open: false);
    // Container lingkaran = leluhur langsung AnimatedRotation.
    final circleFinder = find.ancestor(
      of: find.byType(AnimatedRotation),
      matching: find.byType(Container),
    );
    final circle = t.getSize(circleFinder.first);
    expect(circle, const Size(30, 30));
    // Glif digambar 18px di tengah kotak 30px → margin visual 6px tiap sisi,
    // jadi "+" tidak menyentuh tepi lingkaran (proporsional).
    final icon = t.widget<Icon>(find.byType(Icon));
    expect(icon.size, 18.0);
    expect(icon.size! < circle.width, isTrue);
  });

  testWidgets('rotasi 45° saat terbuka (+ → ✕)', (t) async {
    await pump(t, open: false);
    AnimatedRotation rot() => t.widget<AnimatedRotation>(
      find.byType(AnimatedRotation),
    );
    expect(rot().turns, 0.0);

    await pump(t, open: true);
    expect(rot().turns, 0.125); // 45°
  });
}
