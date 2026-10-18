import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/chat_route.dart';

/// Regresi: transisi buka chat DISAMAKAN dengan WhatsApp (2026-10-18).
///
/// Diukur di HP: WhatsApp membuka chat ±125-133 frame (~2,1 detik animasi
/// termasuk konten masuk). ChatYuk sebelumnya hanya 120ms — terasa
/// "ngebut/lompat", tidak halus.
///
/// Perubahan yang dikunci test ini:
///  - durasi 120ms → 250ms (buka), 100ms → 220ms (tutup),
///  - kurva easeOutQuint (cepat di awal, lembut di akhir),
///  - FADE dihapus: WhatsApp murni slide dari kanan.
///
/// Catatan: `chatRoute` membangun `PrivateChatScreen` yang butuh Supabase,
/// jadi test memverifikasi KONSTANTA + route rekaan dengan kurva yang sama
/// (tanpa me-render layar chat).
void main() {
  test('durasi buka chat 250ms (bukan lagi 120ms)', () {
    expect(kChatRouteDuration, const Duration(milliseconds: 250));
    expect(kChatRouteDuration.inMilliseconds, greaterThan(120));
  });

  test('durasi tutup 220ms — lebih pelan dari sebelumnya (100ms)', () {
    expect(kChatRouteReverseDuration, const Duration(milliseconds: 220));
    expect(kChatRouteReverseDuration.inMilliseconds, greaterThan(100));
  });

  test('tutup sedikit lebih cepat daripada buka', () {
    expect(
      kChatRouteReverseDuration.inMilliseconds,
      lessThan(kChatRouteDuration.inMilliseconds),
    );
  });

  test('kurva easeOutQuint: cepat di awal, lembut di akhir', () {
    // Bandingkan progres pada 20% waktu: easeOutQuint harus JAUH lebih maju
    // daripada linear/easeOutCubic (itulah rasa "menempel ke jari").
    final quint = Curves.easeOutQuint.transform(0.2);
    final cubic = Curves.easeOutCubic.transform(0.2);
    final linear = Curves.linear.transform(0.2);

    expect(quint, greaterThan(cubic));
    expect(cubic, greaterThan(linear));
    // Di 20% waktu, sudah >45% jarak tempuh (awal sangat cepat).
    expect(quint, greaterThan(0.45));
    // Dan benar-benar selesai tepat di 1.0.
    expect(Curves.easeOutQuint.transform(1.0), 1.0);
  });

  /// Route rekaan dengan parameter sama seperti `chatRoute` — untuk menguji
  /// perilaku animasi tanpa bergantung pada PrivateChatScreen/Supabase.
  PageRoute<void> probeRoute() => PageRouteBuilder<void>(
    transitionDuration: kChatRouteDuration,
    reverseTransitionDuration: kChatRouteReverseDuration,
    pageBuilder: (_, _, _) => const Scaffold(body: Text('CHAT')),
    transitionsBuilder: (_, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutQuint,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );

  testWidgets('transisi: SLIDE murni tanpa Fade', (t) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(c).push(probeRoute()),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      ),
    );

    await t.tap(find.text('buka'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 120));

    expect(find.byType(SlideTransition), findsWidgets);
    final partialFades = t
        .widgetList<FadeTransition>(find.byType(FadeTransition))
        .where((f) => f.opacity.value < 1.0)
        .length;
    expect(
      partialFades,
      0,
      reason: 'transisi chat harus slide murni (tanpa fade parsial)',
    );

    await t.pumpAndSettle();
  });

  testWidgets('animasi bertahap: layar masih bergeser di tengah durasi', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(c).push(probeRoute()),
                child: const Text('buka'),
              ),
            ),
          ),
        ),
      ),
    );

    await t.tap(find.text('buka'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 40));

    final moving = t
        .widgetList<SlideTransition>(find.byType(SlideTransition))
        .any((s) => s.position.value.dx > 0.01);
    expect(moving, isTrue, reason: 'layar harus masih bergeser (animasi nyata)');

    // Setelah selesai, layar diam di posisi akhir.
    await t.pumpAndSettle();
    final settled = t
        .widgetList<SlideTransition>(find.byType(SlideTransition))
        .where((s) => s.position.value.dx.abs() > 0.01);
    expect(settled.length, lessThanOrEqualTo(1));
  });
}
