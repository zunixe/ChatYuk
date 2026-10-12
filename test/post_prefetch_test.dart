import 'package:chatyuk/widgets/post/post_prefetch.dart';
import 'package:flutter_test/flutter_test.dart';

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
}