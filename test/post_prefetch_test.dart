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
}
