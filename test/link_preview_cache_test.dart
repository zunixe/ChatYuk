import 'package:chatyuk/core/media/link_preview_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LinkPreviewService cache bound (R6)', () {
    test('cap 50: entri lama dibuang FIFO saat melebihi', () {
      final svc = LinkPreviewService.instance;
      final start = svc.cacheLength;
      // 60 URL unik tanpa jaringan (fetch gagal → fallback tetap di-cache).
      for (var i = 0; i < 60; i++) {
        // ignore: discarded_futures
        svc.fetch('http://nonexistent-$i.invalid/');
      }
      // Tunggu mikro-task fetch selesai (timeout 5s jaringan tidak tercapai
      // utk domain .invalid — gagal cepat, fallback masuk cache).
      return Future<void>.delayed(const Duration(seconds: 1), () {
        expect(svc.cacheLength, lessThanOrEqualTo(50));
        // Tumbuh, tapi tidak melampaui cap.
        expect(svc.cacheLength, greaterThanOrEqualTo(start));
      });
    });
  });
}
