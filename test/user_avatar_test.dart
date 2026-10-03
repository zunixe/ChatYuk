import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/user_avatar.dart';

import 'test_helper.dart';

/// Mengunci kontrak widget avatar MODULAR [UserAvatar] (rumah baru logika
/// `_AsyncAvatar` dari online_users_screen) — dipakai lintas halaman:
/// daftar online, Nearby, panel admin, dll.
///
/// Fokus:
///   * src kosong → huruf inisial (fallback).
///   * src base64 valid → foto tampil (Image).
///   * borderRadius>0 → kotak rounded; =0 → lingkaran.
///   * keepRingForPhoto → ring TRANSPARAN saat foto (gaya kartu Nearby).
///   * anti-kedip: decode gagal TIDAK mengosongkan foto yang sudah tampil.
const _png1px =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
    await prewarmMediaForTest();
  });

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('src kosong → inisial, tanpa foto', (tester) async {
    await tester.pumpWidget(
      wrap(
        const UserAvatar(
          uid: 'u-empty',
          avatarB64: '',
          initial: 'B',
          color: Colors.blue,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('B'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('base64 valid → foto tampil (Image), inisial hilang',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 44,
            height: 44,
            child: UserAvatar(
              uid: 'u-photo',
              avatarB64: _png1px,
              initial: 'S',
              color: Colors.blue,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    });
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('inisial + borderRadius>0 → kotak rounded (bukan lingkaran)',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        const UserAvatar(
          uid: 'u-square',
          avatarB64: '',
          initial: 'B',
          color: Colors.blue,
          borderColor: Colors.blue,
          borderRadius: 8,
        ),
      ),
    );
    await tester.pump();

    final box = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('B'),
            matching: find.byType(Container),
          )
          .first,
    );
    final deco = box.decoration as BoxDecoration;
    expect(deco.shape, BoxShape.rectangle);
    expect(deco.borderRadius, BorderRadius.circular(8));
  });

  testWidgets('keepRingForPhoto → ring TRANSPARAN saat foto tampil',
      (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 44,
            height: 44,
            child: UserAvatar(
              uid: 'u-photo-ring2',
              avatarB64: _png1px,
              initial: 'S',
              color: Colors.blue,
              borderColor: Colors.blue,
              keepRingForPhoto: true,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    });

    final borders = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration)
        .map((c) => c.decoration! as BoxDecoration)
        .where((d) => d.border is Border)
        .map((d) => d.border! as Border)
        .toList();
    expect(borders, isNotEmpty, reason: 'ring disamarkan, bukan dihapus');
    expect(borders.first.top.color, Colors.transparent);
  });

  testWidgets('anti-kedip: src jadi KOSONG → foto lama dipertahankan',
      (tester) async {
    const uid = 'u-antiblink';
    // Frame 1: foto valid → Image tampil.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 44,
            height: 44,
            child: UserAvatar(
              uid: uid,
              avatarB64: _png1px,
              initial: 'S',
              color: Colors.blue,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    });
    expect(find.byType(Image), findsOneWidget);

    // Frame 2: emission kosong (gagal sesaat) → foto lama TIDAK boleh hilang
    // (branch `EMPTY keep-old`).
    await tester.runAsync(() async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 44,
            height: 44,
            child: UserAvatar(
              uid: uid,
              avatarB64: '',
              initial: 'S',
              color: Colors.blue,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    });
    expect(find.byType(Image), findsOneWidget,
        reason: 'foto lama tidak boleh hilang saat emission kosong');
  });
}
