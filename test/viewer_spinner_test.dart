import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/widgets/message/photo_viewer_screen.dart';

/// Mengunci: spinner full-res viewer tidak muncul bila thumbnail sudah tampil.
void main() {
  test('thumb ada → TANPA spinner (walau full belum siap)', () {
    expect(
      viewerShowFullSpinner(hasFull: false, hasThumb: true, hasLoader: true),
      isFalse,
    );
  });

  test('full sudah ada → tanpa spinner', () {
    expect(
      viewerShowFullSpinner(hasFull: true, hasThumb: true, hasLoader: true),
      isFalse,
    );
  });

  test('tak ada thumb & tak ada full → spinner (ada loader)', () {
    expect(
      viewerShowFullSpinner(hasFull: false, hasThumb: false, hasLoader: true),
      isTrue,
    );
  });

  test('tak ada loader → tanpa spinner', () {
    expect(
      viewerShowFullSpinner(hasFull: false, hasThumb: false, hasLoader: false),
      isFalse,
    );
  });
}
