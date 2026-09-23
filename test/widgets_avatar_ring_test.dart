import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/avatar_service.dart';
import 'package:chatyuk/widgets/profile_avatar.dart';

import 'test_helper.dart';

/// Ring warna HANYA untuk placeholder inisial — foto tampil bersih tanpa
/// ring (regresi foto gelap terlihat bercacat biru).
/// Mengunci `profile_avatar.dart`: `_bytes != null → transparent`.
/// Pola: uid '' (get instan, tanpa network) + pump 2s untuk habiskan retry
/// 3×300ms (lihat widgets_session_changes_test.dart).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
    await prewarmMediaForTest();
  });

  tearDown(() {
    AvatarB64Service.instance.clearForUid('u-photo-ring');
  });

  Border? ringOf(WidgetTester tester) {
    final borders = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration)
        .map((c) => c.decoration! as BoxDecoration)
        .where((d) => d.border is Border)
        .map((d) => d.border! as Border)
        .toList();
    if (borders.isEmpty) return null;
    return borders.first;
  }

  testWidgets('inisial (tanpa foto) → ring borderColor', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileAvatar(
            uid: '',
            name: 'Budi',
            size: 44,
            borderColor: Colors.blue,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));

    final border = ringOf(tester);
    expect(border, isNotNull, reason: 'inisial harus punya ring');
    expect(border!.top.color, Colors.blue);
  });

  testWidgets('foto tampil → ring transparan (ukuran tetap)', (tester) async {
    const png1px =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    AvatarB64Service.instance.setForUid('u-photo-ring', png1px);

    await tester.runAsync(() async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProfileAvatar(
              uid: 'u-photo-ring',
              name: 'Sari',
              size: 44,
              borderColor: Colors.blue,
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
    });

    final border = ringOf(tester);
    expect(border, isNotNull, reason: 'ring disamarkan, bukan dihapus');
    expect(border!.top.color, Colors.transparent,
        reason: 'foto tidak boleh kena ring warna');
  });
}
