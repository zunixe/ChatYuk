import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Provider, ChangeNotifierProvider, Consumer;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/providers/admin_provider.dart';
import 'package:chatyuk/providers/riverpod/admin_provider.dart';
import 'package:chatyuk/providers/riverpod/locale_provider.dart';
import 'package:chatyuk/screens/admin_panel/widgets/tablesize_sheet.dart';
import 'package:chatyuk/services/admin_service.dart';

class MockAdminService extends Mock implements AdminService {}

class _TestLocale extends LocaleNotifier {
  final String _lang;
  _TestLocale(this._lang);
  @override
  LocaleState build() => LocaleState(_lang);
}

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
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          localeProvider.overrideWith(() => _TestLocale(lang)),
          adminProvider.overrideWith((ref) => AdminProvider(service: service)),
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
