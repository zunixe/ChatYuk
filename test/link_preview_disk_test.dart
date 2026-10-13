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
}
