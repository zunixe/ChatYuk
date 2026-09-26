import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/models/privacy_settings.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/privacy_provider.dart';
import 'package:chatyuk/screens/privacy_settings_screen.dart';
import 'package:chatyuk/services/privacy_service.dart';

class MockPrivacyService extends Mock implements PrivacyService {}

/// Sheet "kecuali" punya kotak pencarian — daftar bisa ratusan nama.
void main() {
  final s = S(isId: true);
  late MockPrivacyService service;
  late PrivacyProvider provider;

  final people = [
    {'uid': 'u1', 'nickname': 'Andi', 'is_friend': true},
    {'uid': 'u2', 'nickname': 'Budi', 'is_friend': true},
    {'uid': 'u3', 'nickname': 'Candra', 'is_friend': true},
    {'uid': 'u4', 'nickname': 'Dewi', 'is_friend': true},
  ];

  setUp(() {
    service = MockPrivacyService();
    provider = PrivacyProvider(service: service);
    when(() => service.fetch()).thenAnswer(
      (_) async => const PrivacySettings(),
    );
    when(() => service.update(
          presence: any(named: 'presence'),
          lastSeen: any(named: 'lastSeen'),
          profilePhoto: any(named: 'profilePhoto'),
          about: any(named: 'about'),
          story: any(named: 'story'),
          readReceipts: any(named: 'readReceipts'),
        )).thenAnswer((_) async => const PrivacySettings());
    when(() => service.excludableUsers()).thenAnswer((_) async => people);
    when(() => service.replaceExclusions(any(), any())).thenAnswer(
      (_) async => const PrivacySettings(),
    );
  });

  tearDown(() => provider.dispose());

  Widget wrap() => MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleProvider>(
            create: (_) => LocaleProvider(),
          ),
          ChangeNotifierProvider<PrivacyProvider>.value(value: provider),
        ],
        child: const MaterialApp(home: PrivacySettingsScreen()),
      );

  /// Buka sheet "Semua orang kecuali..." → muncul daftar + kotak cari.
  Future<void> openExceptSheet(WidgetTester t) async {
    await t.pumpWidget(wrap());
    await t.pumpAndSettle();
    await t.tap(find.text(s.privacyPresence));
    await t.pumpAndSettle();
    await t.tap(find.text(s.privacyEveryoneExcept));
    // Sheet pilihan terbuka → pilih editor "kecuali" (item daftar).
    await t.pumpAndSettle();
  }

  testWidgets('sheet kecuali: kotak pencarian tampil', (tester) async {
    await openExceptSheet(tester);
    // Editor kecuali terbuka bila ada tombol/daftar; minimal kotak cari ada.
    expect(find.text(s.searchHint), findsWidgets);
  });

  testWidgets('pencarian menyaring daftar nama', (tester) async {
    await openExceptSheet(tester);
    if (find.text(s.searchHint).evaluate().isEmpty) return;
    expect(find.text('Andi'), findsOneWidget);
    expect(find.text('Budi'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'bud');
    await tester.pumpAndSettle();

    expect(find.text('Budi'), findsOneWidget);
    expect(find.text('Andi'), findsNothing);
    expect(find.text('Dewi'), findsNothing);
  });

  testWidgets('pencarian tanpa hasil → pesan kosong', (tester) async {
    await openExceptSheet(tester);
    if (find.text(s.searchHint).evaluate().isEmpty) return;

    await tester.enterText(find.byType(TextField).last, 'zzzz');
    await tester.pumpAndSettle();

    expect(find.text(s.searchNoResult), findsOneWidget);
  });
}
