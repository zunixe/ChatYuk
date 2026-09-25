import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/providers/admin_provider.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/screens/admin_global_setting/widgets/privacy_bypass_tile.dart';
import 'package:chatyuk/services/admin_service.dart';

class MockAdminService extends Mock implements AdminService {}

void main() {
  late MockAdminService service;
  late AdminProvider provider;

  setUp(() {
    service = MockAdminService();
    when(() => service.getPointSettings()).thenAnswer(
      (_) async => {'privacy_bypass_enabled': false},
    );
    when(() => service.setPrivacyBypass(any())).thenAnswer(
      (_) async => {'privacy_bypass_enabled': true},
    );
    provider = AdminProvider(service: service);
  });

  tearDown(() => provider.dispose());

  group('provider passthrough', () {
    test('setPrivacyBypass teruskan nilai + return map', () async {
      final res = await provider.setPrivacyBypass(true);

      expect(res['privacy_bypass_enabled'], isTrue);
      verify(() => service.setPrivacyBypass(true)).called(1);
    });

    test('getPointSettings memuat flag bypass', () async {
      final st = await provider.getPointSettings();

      expect(st['privacy_bypass_enabled'], isFalse);
      verify(() => service.getPointSettings()).called(1);
    });
  });

  group('PrivacyBypassTile', () {
    Future<void> pumpTile(WidgetTester t, {String lang = 'id'}) async {
      SharedPreferences.setMockInitialValues({});
      final lp = LocaleProvider();
      await lp.setLang(lang);
      await t.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AdminProvider>.value(value: provider),
            ChangeNotifierProvider<LocaleProvider>.value(value: lp),
          ],
          child: const MaterialApp(
            home: Scaffold(body: PrivacyBypassTile()),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    // Judul tahan locale: ID dan EN wajib benar.
    for (final lang in ['id', 'en']) {
      testWidgets('judul tampil + switch ikut flag server ($lang)', (t) async {
        await pumpTile(t, lang: lang);

        expect(
          find.text(lang == 'id' ? 'Bypass Privasi' : 'Privacy Bypass'),
          findsOneWidget,
        );
        final sw = t.widget<Switch>(find.byType(Switch));
        expect(sw.value, isFalse);
      });
    }

    testWidgets('tap switch ON → service dipanggil + switch nyala', (t) async {
      await pumpTile(t);

      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();

      verify(() => service.setPrivacyBypass(true)).called(1);
      expect(t.widget<Switch>(find.byType(Switch)).value, isTrue);
    });

    testWidgets('gagal simpan → switch kembali', (t) async {
      when(() => service.setPrivacyBypass(any()))
          .thenThrow(Exception('offline'));
      await pumpTile(t);

      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();

      expect(t.widget<Switch>(find.byType(Switch)).value, isFalse);
    });
  });
}
