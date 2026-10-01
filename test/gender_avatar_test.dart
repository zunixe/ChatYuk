import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/widgets/gender_avatar.dart';

/// Avatar admin panel harus SAMA dengan daftar "Pengguna Online":
///   - latar lingkaran berwarna gender (alpha 0.15)
///   - ring (foregroundDecoration) berwarna gender untuk placeholder inisial
///   - male=biru, female=pink, lain=accent
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Ambil BoxDecoration dari Container GenderAvatar (fill latar).
  BoxDecoration fillOf(WidgetTester tester) {
    final decos = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.decoration is BoxDecoration)
        .map((c) => c.decoration! as BoxDecoration)
        .where((d) => d.color != null)
        .toList();
    expect(decos, isNotEmpty);
    return decos.first;
  }

  /// Ambil border ring (foregroundDecoration).
  Border? ringOf(WidgetTester tester) {
    final borders = tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => c.foregroundDecoration is BoxDecoration)
        .map((c) => c.foregroundDecoration! as BoxDecoration)
        .where((d) => d.border is Border)
        .map((d) => d.border! as Border)
        .toList();
    return borders.isEmpty ? null : borders.first;
  }

  Future<void> pump(WidgetTester tester, String gender) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GenderAvatar(uid: '', name: 'Budi', gender: gender, size: 40),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('male → warna biru (male) di latar & ring', (tester) async {
    await pump(tester, 'male');
    expect(fillOf(tester).color!.toARGB32(),
        AppTheme.male.withValues(alpha: 0.15).toARGB32());
    expect(ringOf(tester)!.top.color, AppTheme.male);
  });

  testWidgets('female → warna pink (female) di latar & ring', (tester) async {
    await pump(tester, 'female');
    expect(fillOf(tester).color!.toARGB32(),
        AppTheme.female.withValues(alpha: 0.15).toARGB32());
    expect(ringOf(tester)!.top.color, AppTheme.female);
  });

  testWidgets('gender tak dikenal → accent', (tester) async {
    await pump(tester, '');
    expect(fillOf(tester).color!.toARGB32(),
        AppTheme.accent.withValues(alpha: 0.15).toARGB32());
    expect(ringOf(tester)!.top.color, AppTheme.accent);
  });

  testWidgets('colorFor memetakan gender dengan benar', (tester) async {
    expect(GenderAvatar.colorFor('male'), AppTheme.male);
    expect(GenderAvatar.colorFor('female'), AppTheme.female);
    expect(GenderAvatar.colorFor('other'), AppTheme.accent);
  });
}
