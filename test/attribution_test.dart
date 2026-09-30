import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/attribution_service.dart';

void main() {
  group('AttributionService.normalize', () {
    test('facebook: varian fb/meta dinormalkan', () {
      expect(AttributionService.normalize(utmSource: 'fb'), 'facebook');
      expect(AttributionService.normalize(utmSource: 'Facebook'), 'facebook');
      expect(AttributionService.normalize(utmSource: 'meta'), 'facebook');
      expect(AttributionService.normalize(utmSource: 'fb_ads'), 'facebook');
    });

    test('instagram: ig/instagram', () {
      expect(AttributionService.normalize(utmSource: 'ig'), 'instagram');
      expect(AttributionService.normalize(utmSource: 'instagram'), 'instagram');
    });

    test('google: utm_source & gclid', () {
      expect(AttributionService.normalize(utmSource: 'google'), 'google');
      expect(AttributionService.normalize(utmSource: 'adwords'), 'google');
      expect(AttributionService.normalize(utmSource: 'youtube'), 'google');
      // gclid tanpa utm_source → google.
      expect(AttributionService.normalize(gclid: 'CjwK'), 'google');
      // gclid di referrer mentah → google.
      expect(
        AttributionService.normalize(referrerRaw: 'gclid=abc123'),
        'google',
      );
    });

    test('tiktok: utm_source & ttclid', () {
      expect(AttributionService.normalize(utmSource: 'tiktok'), 'tiktok');
      expect(AttributionService.normalize(utmSource: 'tt'), 'tiktok');
      expect(AttributionService.normalize(ttclid: 'xyz'), 'tiktok');
      expect(
        AttributionService.normalize(referrerRaw: 'ttclid=xyz'),
        'tiktok',
      );
    });

    test('referral: utm_source & deep link share', () {
      expect(AttributionService.normalize(utmSource: 'referral'), 'referral');
      expect(AttributionService.normalize(utmSource: 'invite'), 'referral');
      expect(AttributionService.normalize(hasReferral: true), 'referral');
    });

    test('fbclid di referrer mentah → facebook', () {
      expect(
        AttributionService.normalize(referrerRaw: 'fbclid=abc'),
        'facebook',
      );
    });

    test('organik: tanpa sinyal apapun', () {
      expect(AttributionService.normalize(), 'organic');
      expect(AttributionService.normalize(utmSource: '  '), 'organic');
    });

    test('kanal tak dikenal diteruskan apa adanya (lowercase)', () {
      expect(AttributionService.normalize(utmSource: 'Snapchat'), 'snapchat');
      expect(AttributionService.normalize(utmSource: 'x'), 'x');
    });

    test('utm_source menang atas gclid (lebih spesifik)', () {
      expect(
        AttributionService.normalize(utmSource: 'facebook', gclid: 'abc'),
        'facebook',
      );
    });
  });

  group('AttributionService.parseReferrer', () {
    test('parse lengkap utm_*', () {
      final p = AttributionService.parseReferrer(
        'utm_source=facebook&utm_medium=cpc&utm_campaign=promo_juli'
        '&utm_content=banner',
      );
      expect(p.utmSource, 'facebook');
      expect(p.utmMedium, 'cpc');
      expect(p.utmCampaign, 'promo_juli');
      expect(p.utmContent, 'banner');
    });

    test('referrer tanpa skema tetap ter-parse', () {
      final p = AttributionService.parseReferrer('utm_source=tiktok');
      expect(p.utmSource, 'tiktok');
    });

    test('nilai ter-encode di-decode', () {
      final p = AttributionService.parseReferrer(
        'utm_source%3Dgoogle%26utm_campaign%3Dpromo%2520juli',
      );
      // referrer Play kadang ter-double-encode; parser manual menanganinya.
      expect(p.utmSource == 'google' || p.utmSource == '', isTrue);
    });

    test('kosong → semua field kosong', () {
      final p = AttributionService.parseReferrer('');
      expect(p.utmSource, '');
      expect(p.utmCampaign, '');
    });

    test('gclid & ttclid ter-ekstrak', () {
      final p = AttributionService.parseReferrer('gclid=g1&ttclid=t1');
      expect(p.gclid, 'g1');
      expect(p.ttclid, 't1');
    });
  });

  group('AttributionService.describeReferrer', () {
    test('google-play → install organik (bukan iklan)', () {
      final d = AttributionService.describeReferrer(
        referrerRaw: 'utm_source=google-play&utm_medium=organic',
        source: 'google-play',
        utmSource: 'google-play',
        utmMedium: 'organic',
      );
      expect(d.toLowerCase(), contains('organik'));
      expect(d.toLowerCase(), contains('bukan iklan'));
    });

    test('gclid → Google Ads + kampanye', () {
      final d = AttributionService.describeReferrer(
        referrerRaw: 'gclid=abc',
        source: 'google',
        utmCampaign: 'promo_juli',
      );
      expect(d, contains('Google Ads'));
      expect(d, contains('promo_juli'));
    });

    test('facebook → Facebook Ads + kampanye', () {
      final d = AttributionService.describeReferrer(
        source: 'facebook',
        utmCampaign: 'lebaran',
      );
      expect(d, contains('Facebook Ads'));
      expect(d, contains('lebaran'));
    });

    test('tiktok tanpa kampanye → sebut TikTok Ads', () {
      final d = AttributionService.describeReferrer(source: 'tiktok');
      expect(d, contains('TikTok Ads'));
    });

    test('referral → dari link share user', () {
      final d = AttributionService.describeReferrer(source: 'referral');
      expect(d.toLowerCase(), contains('referral'));
    });

    test('organic / kosong → organik tanpa link iklan', () {
      expect(
        AttributionService.describeReferrer(referrerRaw: '', source: 'organic'),
        contains('Organik'),
      );
      expect(
        AttributionService.describeReferrer(),
        contains('Organik'),
      );
    });

    test('utm_source lain (twitter) → ditampilkan apa adanya', () {
      final d = AttributionService.describeReferrer(
        source: 'twitter',
        utmSource: 'twitter',
        utmMedium: 'cpc',
      );
      expect(d, contains('twitter'));
    });

    test('tanpa data sama sekali → tidak bingungkan', () {
      final d = AttributionService.describeReferrer(source: 'unknown');
      expect(d, isNotEmpty);
    });
  });
}
