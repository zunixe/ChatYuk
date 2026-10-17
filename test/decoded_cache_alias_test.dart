import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/message/image_decode_core.dart';

/// Mengunci: batas cache decode dihitung per FOTO UNIK, bukan per kunci.
/// Satu foto punya 3–4 kunci alias (base64, path, thumb:id, isi) — dulu cap
/// 32 kunci menggusur `thumb:<id>` → tile album kosong saat mount ulang.
void main() {
  setUp(decodedImageCache.clear);

  DecodedImage pic(int i) => DecodedImage(Uint8List.fromList([i]), 10, 10);

  test('20 foto x 4 alias tetap tersimpan semua', () {
    for (var i = 0; i < decodedCacheMaxUnique; i++) {
      final d = pic(i);
      for (final k in ['b64_$i', 'path_$i', 'thumb:$i', 'data_$i']) {
        putDecodedCache(k.hashCode, d);
      }
    }
    for (var i = 0; i < decodedCacheMaxUnique; i++) {
      expect(getDecodedCache('thumb:$i'.hashCode), isNotNull, reason: 'foto $i');
    }
  });

  test('foto unik ke-21 menggusur yang tertua, bukan alias foto aktif', () {
    for (var i = 0; i <= decodedCacheMaxUnique; i++) {
      final d = pic(i);
      putDecodedCache('a_$i'.hashCode, d);
      putDecodedCache('b_$i'.hashCode, d);
    }
    final unique = (Set<DecodedImage>.identity()
          ..addAll(decodedImageCache.values))
        .length;
    expect(unique, lessThanOrEqualTo(decodedCacheMaxUnique));
    expect(getDecodedCache('b_$decodedCacheMaxUnique'.hashCode), isNotNull);
  });

  test('jumlah kunci tetap bounded', () {
    final d = pic(1);
    for (var i = 0; i < decodedCacheMaxKeys + 50; i++) {
      putDecodedCache('k$i'.hashCode, d);
    }
    expect(decodedImageCache.length, lessThanOrEqualTo(decodedCacheMaxKeys));
  });
}
