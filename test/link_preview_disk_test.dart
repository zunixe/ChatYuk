import 'package:chatyuk/core/media/link_preview_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LinkPreviewService.instance.resetForTest());

  group('LinkPreviewService (LP-A/B)', () {
    test('parseHtml: og:* → data; fallback <title>; lalu host', () {
      final d = LinkPreviewService.parseHtml(
        'https://youtube.com/watch?v=x',
        '<html><head><meta property="og:title" content="Video Keren">'
        '<meta property="og:image" content="https://i.ytimg.com/x.jpg">'
        '<meta property="og:site_name" content="YouTube"></head></html>',
      );
      expect(d.title, 'Video Keren');
      expect(d.image, 'https://i.ytimg.com/x.jpg');
      expect(d.siteName, 'YouTube');

      final t = LinkPreviewService.parseHtml(
        'https://x.com/a',
        '<html><head><title>Judul Saja</title></head></html>',
      );
      expect(t.title, 'Judul Saja');
    });

    test('peek: null sebelum ada', () {
      expect(LinkPreviewService.instance.peek('https://foo/'), isNull);
    });
  });

  group('LinkPreviewService URL filter (chat padat URL)', () {
    test('isPreviewCandidate: halaman web OK, aset gambar ditolak', () {
      expect(
        LinkPreviewService.isPreviewCandidate('https://youtube.com/watch?v=x'),
        isTrue,
      );
      expect(
        LinkPreviewService.isPreviewCandidate('https://example.com/article'),
        isTrue,
      );
      // Ekstensi gambar langsung → bukan kandidat.
      expect(
        LinkPreviewService.isPreviewCandidate('https://x.com/a/b.png'),
        isFalse,
      );
      expect(
        LinkPreviewService.isPreviewCandidate('https://x.com/a/b.JPG?w=1'),
        isFalse,
      );
      // Host generator gambar/diagram AI → bukan kandidat.
      expect(
        LinkPreviewService.isPreviewCandidate(
          'https://image.pollinations.ai/prompt/cat',
        ),
        isFalse,
      );
      expect(
        LinkPreviewService.isPreviewCandidate('https://mermaid.ink/img/abc'),
        isFalse,
      );
      expect(
        LinkPreviewService.isPreviewCandidate('https://quickchart.io/chart?c=x'),
        isFalse,
      );
      // Tak ada host → bukan kandidat.
      expect(LinkPreviewService.isPreviewCandidate('notaurl'), isFalse);
    });

    test('extractUrl: melewati URL aset & menaikkan urlSkipCount', () {
      final svc = LinkPreviewService.instance;
      svc.resetForTest();
      expect(
        svc.extractUrl('lihat https://x.com/a.png ya'),
        isNull,
      );
      expect(svc.urlSkipCount, 1);
      expect(
        svc.extractUrl('baca https://example.com/artikel'),
        'https://example.com/artikel',
      );
      expect(svc.urlSkipCount, 1);
    });
  });
}
