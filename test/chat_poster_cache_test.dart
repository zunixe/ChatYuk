import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/cache/chat_poster_cache.dart';

import 'test_helper.dart';

/// Mengunci cache poster foto chat v2 (grid RGBA 8×8, dibaca sinkron).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List grid(int v) =>
      Uint8List(ChatPosterCache.byteLength)..fillRange(0, ChatPosterCache.byteLength, v);

  setUp(() async {
    mockPathProvider();
    await ChatPosterCache.instance.prewarm();
    await ChatPosterCache.instance.clear();
  });

  test('save → posterSync mengembalikan bytes', () async {
    final bytes = grid(7);
    await ChatPosterCache.instance.save('m1', bytes);
    expect(ChatPosterCache.instance.posterSync('m1'), bytes);
  });

  test('cold start: dibaca dari disk saat RAM kosong', () async {
    await ChatPosterCache.instance.save('disk', grid(3));
    ChatPosterCache.instance.clearMemOnly();
    expect(ChatPosterCache.instance.posterSync('disk'), grid(3));
  });

  test('id kosong / panjang salah (format lama JPEG) → ditolak', () async {
    await ChatPosterCache.instance.save('', grid(1));
    await ChatPosterCache.instance.save('m2', Uint8List(0));
    await ChatPosterCache.instance.save('m3', Uint8List.fromList([1, 2, 3]));
    expect(ChatPosterCache.instance.posterSync(''), isNull);
    expect(ChatPosterCache.instance.posterSync('m2'), isNull);
    expect(ChatPosterCache.instance.posterSync('m3'), isNull);
  });

  test('bounded memori (maks 300)', () async {
    for (var i = 0; i < 340; i++) {
      await ChatPosterCache.instance.save('id$i', grid(i & 0xff));
    }
    expect(ChatPosterCache.instance.memLength, lessThanOrEqualTo(300));
  });

  test('clear menghapus memori', () async {
    await ChatPosterCache.instance.save('gone', grid(9));
    expect(ChatPosterCache.instance.posterSync('gone'), isNotNull);
    await ChatPosterCache.instance.clear();
    expect(ChatPosterCache.instance.posterSync('gone'), isNull);
  });
}
