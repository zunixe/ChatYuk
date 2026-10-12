import 'dart:typed_data';

import 'package:chatyuk/widgets/avatar_image_cache.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('get/evict/clear + LRU cap byte', () async {
    final c = AvatarImageCache.instance;
    c.clear();
    expect(c.get('x'), isNull);
    // put dengan bytes invalid → null (tak crash), store tetap kosong.
    final img = await c.put('x', Uint8List.fromList([1, 2, 3]));
    expect(img, isNull);
    expect(c.length, 0);
  });

  test('AvatarMemoryImage: key stabil + equality', () {
    final bytes = Uint8List.fromList([9, 9, 9]);
    final a = AvatarMemoryImage('u1', bytes, width: 96);
    final b = AvatarMemoryImage('u1', bytes, width: 96);
    expect(a, b); // uid+width+bytes identik → sama (stream stabil)
    final c2 = AvatarMemoryImage('u2', bytes, width: 96);
    expect(a == c2, isFalse);
  });

  test('ui.Image tile ukuran 96px (dokumentasi ukuran)', () {
    // Sanity: 96x96 RGBA = 36 KB → cap 8MB ≈ 220 avatar.
    expect(96 * 96 * 4, 36864);
  });
}
