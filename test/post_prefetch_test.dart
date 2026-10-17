import 'dart:typed_data';

import 'package:chatyuk/core/cache/post_photo_cache.dart';
import 'package:chatyuk/widgets/post/post_prefetch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'test_helper.dart';

void main() {
  setUp(PostPrefetch.reset);
  tearDown(PostPrefetch.reset);

  test('pathsOf: multi images + single imagePath', () {
    expect(PostPrefetch.pathsOf({'images': ['a', 'b']}), ['a', 'b']);
    expect(PostPrefetch.pathsOf({'imagePath': 'x'}), ['x']);
    expect(PostPrefetch.pathsOf({}), isEmpty);
    expect(PostPrefetch.pathsOf({'images': ['', 'y']}), ['y']);
  });

  test('warmAheadFrom: aman di index ekstrem (tak melempar)', () {
    final posts = [for (var i = 0; i < 3; i++) {'imagePath': 'p$i'}];
    // Index terakhir & melebihi panjang → no-op aman.
    PostPrefetch.warmAheadFrom(posts, 2);
    PostPrefetch.warmAheadFrom(posts, 99);
    PostPrefetch.warmAheadFrom(const [], 0);
  });

  testWidgets('warmPosts: foto utama feed + sisa tile (bounded)',
      (tester) async {
    mockPathProvider();
    final jpeg = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 8, height: 8)),
    );
    final calls = <String>[];
    PostPhotoCache.thumbDownloader = (p, w) async {
      calls.add('$w:$p');
      return jpeg;
    };
    addTearDown(() => PostPhotoCache.thumbDownloader = null);

    await tester.runAsync(() async {
      PostPrefetch.warmPosts([
        {
          'images': ['a', 'b', 'c', 'd', 'e']
        }
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });

    expect(calls, contains('1080:a'), reason: 'foto utama = varian feed');
    expect(calls, containsAll(['400:b', '400:c', '400:d']),
        reason: 'foto carousel = varian tile');
    expect(calls.any((c) => c.endsWith(':e')), isFalse,
        reason: 'dibatasi maxPhotosPerPost=4');
  });
}
