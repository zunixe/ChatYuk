import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/cache/chat_poster_cache.dart';

import 'test_helper.dart';

/// Mengunci cache poster foto chat (placeholder sinkron anti-kedip).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    mockPathProvider();
    await ChatPosterCache.instance.prewarm();
    await ChatPosterCache.instance.clear();
  });

  test('save → posterSync mengembalikan bytes', () async {
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    await ChatPosterCache.instance.save('m1', bytes);
    expect(ChatPosterCache.instance.posterSync('m1'), bytes);
  });

  test('messageId kosong / bytes kosong → tidak disimpan', () async {
    await ChatPosterCache.instance.save('', Uint8List.fromList([1]));
    await ChatPosterCache.instance.save('m2', Uint8List(0));
    expect(ChatPosterCache.instance.posterSync(''), isNull);
    expect(ChatPosterCache.instance.posterSync('m2'), isNull);
  });

  test('bounded memori (maks 300)', () async {
    for (var i = 0; i < 340; i++) {
      await ChatPosterCache.instance.save(
        'id$i',
        Uint8List.fromList([i & 0xff]),
      );
    }
    expect(ChatPosterCache.instance.memLength, lessThanOrEqualTo(300));
  });

  test('clear menghapus memori', () async {
    await ChatPosterCache.instance.save('gone', Uint8List.fromList([9]));
    expect(ChatPosterCache.instance.posterSync('gone'), isNotNull);
    await ChatPosterCache.instance.clear();
    expect(ChatPosterCache.instance.posterSync('gone'), isNull);
  });
}
