import 'package:chatyuk/core/cache/post_photo_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('statsAndReset: kembalikan delta lalu nol-kan', () {
    PostPhotoCache.statsAndReset(); // bersihkan
    PostPhotoCache.statRam = 5;
    PostPhotoCache.statDisk = 3;
    PostPhotoCache.statNetwork = 1;
    PostPhotoCache.statDecode = 2;
    final label = PostPhotoCache.statsAndReset();
    expect(label, contains('ram=5'));
    expect(label, contains('disk=3'));
    expect(label, contains('net=1'));
    expect(label, contains('decode=2'));
    // Sudah di-reset → label berikutnya nol semua.
    final second = PostPhotoCache.statsAndReset();
    expect(second, contains('ram=0'));
    expect(second, contains('net=0'));
  });
}
