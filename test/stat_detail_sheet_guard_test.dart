import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/providers/admin_provider.dart';
import 'package:chatyuk/providers/riverpod/admin_provider.dart';
import 'package:chatyuk/providers/riverpod/locale_provider.dart';
import 'package:chatyuk/screens/admin_panel/widgets/stat_detail_sheet.dart';
import 'package:chatyuk/services/admin_service.dart';
import 'package:chatyuk/config/theme.dart';

class MockAdminService extends Mock implements AdminService {}

class _TestLocale extends LocaleNotifier {
  @override
  LocaleState build() => const LocaleState('id');
}

/// Regresi: kartu Ringkasan/Poin bisa dibuka 2x sheet kalau di-tap cepat,
/// karena `showStatDetailSheet` memuat data (`await`) SEBELUM menampilkan
/// sheet. Guard `_statSheetOpen` harus memblok tap kedua.
void main() {
  late MockAdminService service;

  setUp(() {
    resetStatDetailSheetGuardForTest();
    service = MockAdminService();
    when(() => service.listStatsUsers(any(), limit: any(named: 'limit'), offset: any(named: 'offset')))
        .thenAnswer((_) async => {'items': <dynamic>[], 'total': 0});
  });

  Future<void> pumpSheet(WidgetTester t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          localeProvider.overrideWith(_TestLocale.new),
          adminProvider.overrideWith((ref) => AdminProvider(service: service)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => showStatDetailSheet(
                  ctx,
                  ('Pengguna', '10', Icons.people, Colors.blue, 'users_all'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('tap dobel cepat → hanya SATU sheet', (tester) async {
    await pumpSheet(tester);
    // Tap 2x beruntun tanpa menunggu sheet sempat muncul.
    await tester.tap(find.text('open'));
    await tester.tap(find.text('open'));
    await tester.pump(); // proses microtask/await
    await tester.pump(const Duration(milliseconds: 50));

    // Sheet = ModalBottomSheet. Harus tepat 1.
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('tutup sheet lalu buka lagi → boleh (guard di-reset)',
      (tester) async {
    await pumpSheet(tester);
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BottomSheet), findsOneWidget);

    // Tutup.
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);

    // Buka lagi → harus muncul.
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BottomSheet), findsOneWidget);
  });
}
