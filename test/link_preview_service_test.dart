import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:chatyuk/core/media/link_preview_service.dart';

Future<T> withClient<T>(Future<T> Function() body, MockClient client) =>
    http.runWithClient(body, () => client);

void main() {
  group('LinkPreviewService.fetch', () {
    test('parse Open Graph lengkap (og:title/description/image/site_name)',
        () async {
      final client = MockClient(
        (req) async => http.Response(
          '''
<html><head>
<meta property="og:title" content="Judul Artikel" />
<meta property="og:description" content="Deskripsi singkat" />
<meta property="og:image" content="https://ex.com/img.jpg" />
<meta property="og:site_name" content="Contoh" />
</head></html>''',
          200,
        ),
      );
      final data = await withClient(
        () => LinkPreviewService.instance.fetch('https://ex.com/a'),
        client,
      );
      expect(data, isNotNull);
      expect(data!.title, 'Judul Artikel');
      expect(data.description, 'Deskripsi singkat');
      expect(data.image, 'https://ex.com/img.jpg');
      expect(data.siteName, 'Contoh');
    });

    test('content sebelum property juga terbaca (urutan atribut terbalik)',
        () async {
      final client = MockClient(
        (req) async => http.Response(
          '<meta content="Deskripsi X" property="og:description">',
          200,
        ),
      );
      final data = await withClient(
        () => LinkPreviewService.instance.fetch('https://ex.com/b'),
        client,
      );
      expect(data!.description, 'Deskripsi X');
    });

    test('tanpa og:title → fallback ke <title>', () async {
      final client = MockClient(
        (req) async => http.Response(
          '<html><head><title>Judul HTML</title></head></html>',
          200,
        ),
      );
      final data = await withClient(
        () => LinkPreviewService.instance.fetch('https://ex.com/c'),
        client,
      );
      expect(data!.title, 'Judul HTML');
    });

    test('tanpa title sama sekali → pakai host', () async {
      final client = MockClient(
        (req) async => http.Response('<html></html>', 200),
      );
      final data = await withClient(
        () => LinkPreviewService.instance.fetch('https://contoh.id/x'),
        client,
      );
      expect(data!.title, 'contoh.id');
      expect(data.siteName, 'contoh.id');
    });

    test('deskripsi fallback ke meta name=description', () async {
      final client = MockClient(
        (req) async => http.Response(
          '<meta name="description" content="Desc via name">',
          200,
        ),
      );
      final data = await withClient(
        () => LinkPreviewService.instance.fetch('https://ex.com/d'),
        client,
      );
      expect(data!.description, 'Desc via name');
    });

    test('status != 200 → fallback host (tanpa crash)', () async {
      final client = MockClient((req) async => http.Response('err', 500));
      final data = await withClient(
        () => LinkPreviewService.instance.fetch('https://gagal.id/p'),
        client,
      );
      expect(data, isNotNull);
      expect(data!.title, 'gagal.id');
    });

    test('hasil di-cache: request kedua tidak hit jaringan lagi', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        return http.Response('<title>Cache Me</title>', 200);
      });
      final url = 'https://cache.id/${DateTime.now().microsecondsSinceEpoch}';
      final a = await withClient(
        () => LinkPreviewService.instance.fetch(url),
        client,
      );
      final b = await withClient(
        () => LinkPreviewService.instance.fetch(url),
        client,
      );
      expect(a!.title, 'Cache Me');
      expect(b!.title, 'Cache Me');
      expect(calls, 1);
    });

    test('URL tanpa scheme → fallback, tidak crash', () async {
      final data = await LinkPreviewService.instance.fetch('bukan-url');
      expect(data, isNotNull);
      expect(data!.url, 'bukan-url');
    });
  });
}
