import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/config/theme.dart';
import 'package:chatyuk/widgets/person_avatar.dart';

import 'test_helper.dart';

/// Mengunci `PersonAvatar` — sumber tunggal warna/ring/badge avatar orang
/// supaya SATU orang konsisten di semua halaman (Online, chat, profil, dll).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
    await prewarmMediaForTest();
  });

  test('colorFor: male biru, female merah muda, lain accent', () {
    expect(PersonAvatar.colorFor('male'), AppTheme.male);
    expect(PersonAvatar.colorFor('female'), AppTheme.female);
    expect(PersonAvatar.colorFor(''), AppTheme.accent);
    expect(PersonAvatar.colorFor('other'), AppTheme.accent);
    expect(PersonAvatar.colorFor('male'), isNot(PersonAvatar.colorFor('female')));
  });

  Future<void> pump(WidgetTester tester, {required String gender}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonAvatar(
            uid: '',
            name: 'Budi',
            gender: gender,
            size: 40,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('male → inisial + ring biru (warna gender)', (tester) async {
    await pump(tester, gender: 'male');
    final containers = tester.widgetList<Container>(find.byType(Container));
    // Ada kontainer circle dengan warna male@15% dan ring male.
    final hasMaleBg = containers.any((c) {
      final d = c.decoration;
      return d is BoxDecoration && d.color == AppTheme.male.withValues(alpha: 0.15);
    });
    expect(hasMaleBg, isTrue, reason: 'latar tint warna gender male');
  });

  testWidgets('female → warna gender female (bukan male)', (tester) async {
    await pump(tester, gender: 'female');
    final containers = tester.widgetList<Container>(find.byType(Container));
    final hasFemaleBg = containers.any((c) {
      final d = c.decoration;
      return d is BoxDecoration &&
          d.color == AppTheme.female.withValues(alpha: 0.15);
    });
    expect(hasFemaleBg, isTrue);
  });

  testWidgets('status badge tampil bila status diisi', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonAvatar(
            uid: '',
            name: 'Budi',
            gender: 'male',
            size: 40,
            status: 'online',
          ),
        ),
      ),
    );
    await tester.pump();
    // Badge = container bulat warna statusColor(online).
    final containers = tester.widgetList<Container>(find.byType(Container));
    final hasDot = containers.any((c) {
      final d = c.decoration;
      return d is BoxDecoration &&
          d.shape == BoxShape.circle &&
          d.color == AppTheme.online &&
          c.constraints?.maxWidth == 40 * 0.28;
    });
    expect(hasDot, isTrue);
  });
}
