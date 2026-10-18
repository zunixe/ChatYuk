import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chatyuk/core/media/link_preview_service.dart';

/// Link pendek Shopee (s.shopee.co.id) memberi metadata PRODUK hanya ke UA
/// pengambil-preview (WhatsApp); UA browser = halaman BERANDA. Fixture = HTML
/// asli hasil curl 2026-10-18.
void main() {
  final waHtml = File('test/fixtures/shopee_short_link_whatsapp_ua.html').readAsStringSync();
  final browserHtml = File('test/fixtures/shopee_short_link_browser_ua.html').readAsStringSync();

  test('fetch memakai UA preview → judul/deskripsi/gambar PRODUK', () async {
    final uas = <String>[];
    final client = MockClient((req) async {
      final ua = req.headers['User-Agent'] ?? '';
      uas.add(ua);
      return http.Response(
        ua == LinkPreviewService.previewUserAgent ? waHtml : browserHtml,
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });
    final url = 'https://s.shopee.co.id/7KxpwnGmyj?t=${DateTime.now().microsecondsSinceEpoch}';
    final d = await http.runWithClient(() => LinkPreviewService.instance.fetch(url), () => client);
    expect(uas.first, LinkPreviewService.previewUserAgent);
    expect(d!.title, startsWith('Jual LED Diode Round 5mm'));
    expect(d.description, contains('Gratis Ongkir, Promo COD, & Cashback'));
    expect(d.image, contains('susercontent.com'));
  });

  test('situs menolak UA preview (tanpa metadata) → cadangan UA browser', () async {
    final client = MockClient((req) async {
      final ua = req.headers['User-Agent'] ?? '';
      return ua == LinkPreviewService.previewUserAgent
          ? http.Response('<html><title>blocked</title></html>', 200)
          : http.Response(
              '<meta property="og:title" content="Halaman Asli">'
              '<meta property="og:image" content="https://x.id/a.jpg">',
              200,
            );
    });
    final url = 'https://contoh.id/${DateTime.now().microsecondsSinceEpoch}';
    final d = await http.runWithClient(() => LinkPreviewService.instance.fetch(url), () => client);
    expect(d!.title, 'Halaman Asli');
  });

  test('dekode entitas HTML (judul tak lagi "&amp;" mentah)', () {
    final d = LinkPreviewService.parseHtml('https://s.shopee.co.id/x', browserHtml);
    expect(d.title, 'Shopee Indonesia | Situs Belanja Online Terlengkap & Terpercaya');
    expect(LinkPreviewService.decodeHtmlEntities('Instagram (&#064;instagram) &#x2022; profil'),
        'Instagram (@instagram) • profil');
    expect(LinkPreviewService.decodeHtmlEntities('a.jpg?w=1&amp;h=2'), 'a.jpg?w=1&h=2');
    expect(LinkPreviewService.decodeHtmlEntities('&bogus; tetap'), '&bogus; tetap');
  });
}
