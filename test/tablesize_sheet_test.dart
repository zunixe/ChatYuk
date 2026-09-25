import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/providers/admin_provider.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/screens/admin_panel/widgets/tablesize_sheet.dart';
import 'package:chatyuk/services/admin_service.dart';

class MockAdminService extends Mock implements AdminService {}

/// Widget test diagnosis: sheet breakdown tabel harus render baris tanpa
/// NoSuchMethodError (abu-abu di release = build gagal).
void main() {
  late MockAdminService service;

  setUp(() {
    service = MockAdminService();
    when(() => service.getTableSizes()).thenAnswer(
      (_) async => {
        'db_bytes': 74034323,
        'tables': [
          {
            'schema': 'cron',
            'table': 'job_run_details',
            'total_bytes': 34996224,
            'table_bytes': 32505856,
            'index_bytes': 2457600,
            'rows_est': 104602,
          },
        ],
      },
    );
  });

  Future<void> pumpSheet(WidgetTester t, {String lang = 'id'}) async {
    final admin = AdminProvider(service: service);
    addTearDown(admin.dispose);
    SharedPreferences.setMockInitialValues({});
    final lp = LocaleProvider();
    await lp.setLang(lang);
    await t.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AdminProvider>.value(value: admin),
          ChangeNotifierProvider<LocaleProvider>.value(value: lp),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () => showTableSizeSheet(ctx),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  // Judul tahan locale: ID dan EN wajib benar.
  for (final lang in ['id', 'en']) {
    testWidgets('sheet tampil + render 1 baris tabel ($lang)', (t) async {
      await pumpSheet(t, lang: lang);
      expect(
        find.text(
          lang == 'id' ? 'Rincian Ukuran Tabel' : 'Table Size Breakdown',
        ),
        findsOneWidget,
      );
      expect(find.text('cron.job_run_details'), findsOneWidget);
    });
  }
}
