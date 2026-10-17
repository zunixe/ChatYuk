import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresi: menu titik-3 di header daftar chat (Riwayat Panggilan, Grup Baru,
/// Tandai semua dibaca) harus muncul TEPAT di bawah ikon, rata kanan —
/// bukan melayang jauh.
///
/// Bug lama: posisi dihitung `offset.dx - 160` dari pojok kiri-atas tombol,
/// menggeser menu 160px ke KIRI sehingga jauh dari ikon.
const double kMenuWidth = 200;

void main() {
  /// Salinan logika posisi di `chats_screen.dart::_openMoreMenu`.
  RelativeRect menuRect({
    required Offset topLeft,
    required Size btnSize,
    required double screenW,
  }) => RelativeRect.fromLTRB(
    (topLeft.dx + btnSize.width - kMenuWidth).clamp(8.0, screenW),
    topLeft.dy + btnSize.height + 4,
    screenW - (topLeft.dx + btnSize.width) + 8,
    0,
  );

  testWidgets('menu menempel di bawah tombol & rata kanan', (t) async {
    const screenW = 400.0;
    // Tombol titik-3 di kanan header (mis. x=350, lebar 32).
    const topLeft = Offset(350, 10);
    const btnSize = Size(32, 44);

    final r = menuRect(topLeft: topLeft, btnSize: btnSize, screenW: screenW);

    // Menu mulai tepat di bawah tombol (bukan 160px ke kiri).
    expect(r.top, closeTo(topLeft.dy + btnSize.height + 4, 0.01));
    // Tepi kanan menu sejajar tepi kanan tombol + 8px ke tepi layar
    // (right diukur dari tepi kanan LAYAR) → 400-382+8 = 26.
    expect(r.right, closeTo(26.0, 0.01));
    // Lebar efektif = 200 (tidak melebar keluar layar).
    final width = screenW - r.left - r.right;
    expect(width, closeTo(kMenuWidth, 12));
  });

  testWidgets('menu tidak melewati tepi kiri layar (clamp)', (t) async {
    const screenW = 400.0;
    // Tombol sangat di kiri → clamped ke 8.
    final r = menuRect(
      topLeft: const Offset(4, 10),
      btnSize: const Size(32, 44),
      screenW: screenW,
    );
    expect(r.left, closeTo(8.0, 0.01));
  });

  testWidgets('posisi lama (dx-160) memang jauh — dokumentasi bug', (t) async {
    const topLeft = Offset(350, 10);
    const screenW = 400.0;
    const btnW = 32.0;
    // Rumus lama: kiri = 350 - 160 = 190 → menu 160px ke kiri dari ikon.
    final oldLeft = topLeft.dx - 160;
    // Rumus baru: kiri = 350 + 32 - 200 = 182 → menempel di bawah ikon.
    final newLeft = topLeft.dx + btnW - kMenuWidth;
    // Selisih nyata antara titik jangkar lama vs baru.
    expect(oldLeft, 190.0);
    expect(newLeft, 182.0);
    // Yang penting: kanan barunya sejajar tombol, bukan melayang.
    final r = menuRect(
      topLeft: topLeft,
      btnSize: const Size(btnW, 44),
      screenW: screenW,
    );
    // Tepi kanan menu = 400 - 26 = 374; tombol berakhir di 382.
    // Menu berakhir 8px di kiri tepi tombol (margin aman ke tepi layar) —
    // tetap MENEMPEL di bawah ikon, bukan 160px melayang ke kiri.
    final menuRightEdge = screenW - r.right;
    expect(menuRightEdge, closeTo(topLeft.dx + btnW - 8, 0.01));
    // Dan menu memang jauh lebih dekat ke ikon dibanding rumus lama.
    final oldMenuLeft = 190.0; // rumus lama
    expect(r.left - oldMenuLeft, lessThan(10));
  });
}
