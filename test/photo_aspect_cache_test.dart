import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/core/cache/photo_aspect_cache.dart';

/// Mengunci cache aspek foto chat (anti "bubble melompat" saat cold start).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await PhotoAspectCache.instance.clear();
    await PhotoAspectCache.instance.prewarm();
  });

  test('remember → aspectOf mengembalikan w/h', () {
    PhotoAspectCache.instance.remember('m1', 1080, 1440);
    expect(PhotoAspectCache.instance.aspectOf('m1'), closeTo(0.75, 1e-9));
  });

  test('dimensi tidak valid diabaikan', () {
    PhotoAspectCache.instance.remember('m2', 0, 100);
    PhotoAspectCache.instance.remember('m3', 100, -1);
    PhotoAspectCache.instance.remember('', 10, 10);
    expect(PhotoAspectCache.instance.aspectOf('m2'), isNull);
    expect(PhotoAspectCache.instance.aspectOf('m3'), isNull);
    expect(PhotoAspectCache.instance.aspectOf(''), isNull);
  });

  test('bounded: maksimal 500 entri (FIFO)', () {
    for (var i = 0; i < 620; i++) {
      PhotoAspectCache.instance.remember('id$i', 100, 100 + (i % 7));
    }
    expect(PhotoAspectCache.instance.length, lessThanOrEqualTo(500));
  });

  test('flushNow menulis ke SharedPreferences', () async {
    PhotoAspectCache.instance.remember('persist1', 1000, 1000);
    await PhotoAspectCache.instance.flushNow();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('chat_photo_aspect_v1') ?? '';
    expect(raw, contains('persist1'));
  });

  test('clear menghapus memori + preferensi', () async {
    PhotoAspectCache.instance.remember('gone', 10, 20);
    await PhotoAspectCache.instance.flushNow();
    await PhotoAspectCache.instance.clear();
    expect(PhotoAspectCache.instance.aspectOf('gone'), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('chat_photo_aspect_v1'), isNull);
  });
}
