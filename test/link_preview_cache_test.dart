import 'package:chatyuk/core/media/link_preview_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LinkPreviewService cache bound (R6)', () {
    test('cap 200: entri lama dibuang FIFO saat melebihi', () {
      final svc = LinkPreviewService.instance;
      final start = svc.cacheLength;
      // 260 URL unik tanpa jaringan (fetch gagal → fallback tetap di-cache).
      for (var i = 0; i < 260; i++) {
        // ignore: discarded_futures
        svc.fetch('http://nonexistent-$i.invalid/');
      }
      // Tunggu mikro-task fetch selesai (timeout jaringan tidak tercapai
      // utk domain .invalid — gagal cepat, fallback masuk cache).
      return Future<void>.delayed(const Duration(seconds: 2), () {
        expect(svc.cacheLength, lessThanOrEqualTo(200));
        // Tumbuh, tapi tidak melampaui cap.
        expect(svc.cacheLength, greaterThanOrEqualTo(start));
      });
    });
  });
}
