import 'package:flutter_test/flutter_test.dart';
import 'package:chatyuk/core/media/link_preview_service.dart';
import 'package:chatyuk/widgets/link_preview_image.dart';

/// Regresi PERF: rasio foto kartu link dulu dibaca dari DISK secara SINKRON
/// (`MediaDiskCache.readSync` → `File.readAsBytesSync`) setiap bubble link
/// di-mount → scroll chat lama tersendat (I/O UI thread seukuran file gambar).
///
/// Sekarang rasio dihitung SEKALI setelah decode lalu disimpan di cache RAM
/// service; `peekAspect` berikutnya nol I/O.
void main() {
  setUp(() => LinkPreviewService.instance.resetForTest());

  test('peekAspect kosong di awal (tanpa I/O disk)', () {
    expect(LinkPreviewImage.peekAspect('https://x/img.jpg'), isNull);
  });

  test('putAspect lalu peekAspect mengembalikan nilai sama (RAM)', () {
    const url = 'https://x/img.jpg';
    LinkPreviewService.instance.putAspect(url, 0.786);
    expect(LinkPreviewImage.peekAspect(url), closeTo(0.786, 1e-9));
  });

  test('peekAspect untuk URL beda tetap null', () {
    LinkPreviewService.instance.putAspect('https://x/a.jpg', 1.5);
    expect(LinkPreviewImage.peekAspect('https://x/b.jpg'), isNull);
  });

  test('rasio tak valid ditolak (tak meracuni cache)', () {
    const url = 'https://x/bad.jpg';
    LinkPreviewService.instance.putAspect(url, 0);
    expect(LinkPreviewImage.peekAspect(url), isNull);

    LinkPreviewService.instance.putAspect(url, double.nan);
    expect(LinkPreviewImage.peekAspect(url), isNull);

    LinkPreviewService.instance.putAspect(url, double.infinity);
    expect(LinkPreviewImage.peekAspect(url), isNull);
  });

  test('URL kosong aman', () {
    LinkPreviewService.instance.putAspect('', 1.2);
    expect(LinkPreviewImage.peekAspect(''), isNull);
  });

  test('cache dibatasi (FIFO) — tidak tumbuh tanpa batas', () {
    for (var i = 0; i < 260; i++) {
      LinkPreviewService.instance.putAspect('https://x/$i.jpg', 1.0);
    }
    // Entri paling awal terbuang, entri terbaru tetap ada.
    expect(LinkPreviewImage.peekAspect('https://x/0.jpg'), isNull);
    expect(LinkPreviewImage.peekAspect('https://x/259.jpg'), 1.0);
  });
}
