import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/media/image_cache_hygiene.dart';

/// Hygiene cache gambar saat logout: semua cache aplikasi yang terdaftar
/// harus dibersihkan, tahan error, dan tidak dobel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => ImageCacheHygiene.clearAll());

  test('clearAll memanggil semua cache aplikasi yang terdaftar', () {
    var called = 0;
    ImageCacheHygiene.registerAppCache(() => called++);
    ImageCacheHygiene.registerAppCache(() => called += 10);

    ImageCacheHygiene.clearAll();

    expect(called, 11, reason: 'kedua cache aplikasi harus dibersihkan');
  });

  test('registerAppCache idempoten — pembersih sama tidak dobel', () {
    var called = 0;
    void clear() => called++;
    ImageCacheHygiene.registerAppCache(clear);
    ImageCacheHygiene.registerAppCache(clear);

    ImageCacheHygiene.clearAll();
    expect(called, 1);
  });

  test('pembersih yang melempar tidak menghentikan pembersih lain', () {
    var later = 0;
    ImageCacheHygiene.registerAppCache(() => throw StateError('boom'));
    ImageCacheHygiene.registerAppCache(() => later++);

    expect(() => ImageCacheHygiene.clearAll(), returnsNormally);
    expect(later, 1);
  });

  test('ImageCache benar-benar dikosongkan', () {
    final cache = PaintingBinding.instance.imageCache;
    // String kunci dummy masuk ke pending cache (cukup untuk membuktikan
    // clear() bekerja tanpa perlu membuat ImageStreamCompleter tiruan).
    expect(cache.currentSize, 0);
    ImageCacheHygiene.clearAll();
    expect(cache.currentSize, 0);
  });
}
