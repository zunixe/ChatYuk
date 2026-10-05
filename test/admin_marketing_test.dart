import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import 'package:chatyuk/providers/admin_provider.dart';
import 'package:chatyuk/services/admin_service.dart';

class MockAdminService extends Mock implements AdminService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MockAdminService service;
  late AdminProvider provider;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    service = MockAdminService();
    provider = AdminProvider(service: service);
  });

  tearDown(() => provider.dispose());

  group('AdminMarketingMx', () {
    test('fetchMarketing mengisi campaigns + stats', () async {
      when(() => service.emailCampaignsPage(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => [
            {'id': 1, 'name': 'Promo', 'status': 'draft'},
          ]);
      when(() => service.emailStats())
          .thenAnswer((_) async => {'sent_total': 10});

      await provider.fetchMarketing();
      expect(provider.marketingCampaigns.length, 1);
      expect(provider.marketingCampaigns.first['name'], 'Promo');
      expect(provider.marketingStats?['sent_total'], 10);
      expect(provider.marketingError, isNull);
    });

    test('fetchMarketing gagal → marketingError di-set, tidak throw', () async {
      when(() => service.emailCampaignsPage(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenThrow(Exception('offline'));
      when(() => service.emailStats())
          .thenThrow(Exception('offline'));
      await provider.fetchMarketing();
      expect(provider.marketingError, isNotNull);
    });

    test('saveCampaign mengirim id+segment + refresh', () async {
      when(() => service.emailCampaignSave(
            id: any(named: 'id'),
            name: any(named: 'name'),
            subject: any(named: 'subject'),
            html: any(named: 'html'),
            segment: any(named: 'segment'),
          )).thenAnswer((_) async => {'ok': true, 'id': 7});
      when(() => service.emailCampaignsPage(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => []);
      when(() => service.emailStats()).thenAnswer((_) async => {});

      final id = await provider.saveCampaign(
        name: 'n',
        subject: 's',
        html: '<p>x</p>',
        segment: {'type': 'all_registered'},
      );
      expect(id, 7);
      verify(() => service.emailCampaignSave(
            id: any(named: 'id'),
            name: 'n',
            subject: 's',
            html: '<p>x</p>',
            segment: any(named: 'segment'),
          )).called(1);
    });

    test('sendCampaign sukses → "ok:<n>"', () async {
      when(() => service.emailEnqueue(1))
          .thenAnswer((_) async => {'ok': true, 'recipients': 42});
      when(() => service.emailCampaignsPage(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => []);
      when(() => service.emailStats()).thenAnswer((_) async => {});

      final res = await provider.sendCampaign(1);
      expect(res, 'ok:42');
    });

    test('sendCampaign ditolak → alasan dikembalikan', () async {
      when(() => service.emailEnqueue(1))
          .thenAnswer((_) async => {'ok': false, 'reason': 'disabled'});
      when(() => service.emailCampaignsPage(
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => []);
      when(() => service.emailStats()).thenAnswer((_) async => {});

      expect(await provider.sendCampaign(1), 'disabled');
    });

    test('estimateSegment → count', () async {
      when(() => service.emailEstimateSegment(any()))
          .thenAnswer((_) async => {'count': 123});
      expect(
        await provider.estimateSegment({'type': 'all_registered'}),
        123,
      );
    });
  });

  group('Delta → HTML (email)', () {
    test('paragraf + bold terkonversi ke tag', () {
      final delta = [
        {'insert': 'Halo '},
        {
          'insert': 'dunia',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ];
      final html = QuillDeltaToHtmlConverter(
        List<Map<String, dynamic>>.from(delta),
        ConverterOptions.forEmail(),
      ).convert();
      expect(html.toLowerCase(), contains('<p>'));
      expect(html.toLowerCase(), contains('<strong>'));
      expect(html, contains('dunia'));
    });
  });
}
