import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/core/cache/message_cache.dart';

/// Regresi: bintang di bubble pesan "munculnya telat" (tidak instan saat chat
/// dibuka / cold start).
///
/// Akar masalah: entri `starred:<chat>` dulu berbagi SATU map memori (cap 60,
/// FIFO) dengan `profile:`/timeline. Karena preload `profile:` & `starred:`
/// jalan BERSAMAAN saat bootstrap, entri `starred:` bisa ter-evict → `peek`
/// (sinkron) kosong → bintang baru muncul setelah stream realtime datang.
///
/// Sekarang `starred:`/`reactions:` punya bucket memori SENDIRI.
///
/// Catatan: di test, disk (SQLite/Keystore) tidak tersedia → hanya lapisan
/// MEMORI yang diuji; itu justru jalur yang dipakai `peekCachedStarred`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = MessageCache.instance;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    cache.trimMemCache();
  });

  test('starred TIDAK ter-evict oleh banyak entri profile', () async {
    for (var i = 0; i < 120; i++) {
      await cache.saveRawObj('profile:uid$i', {'name': 'User $i'});
    }
    await cache.saveRawObj('starred:chat1', {
      'ids': ['m1', 'm2'],
    });

    final peeked = cache.peekRawObj('starred:chat1');
    expect(
      peeked['ids'],
      isNotNull,
      reason: 'bintang harus instan (peek), bukan kosong',
    );
    expect(List<String>.from(peeked['ids'] as List), ['m1', 'm2']);
  });

  test('reactions juga punya bucket sendiri', () async {
    for (var i = 0; i < 120; i++) {
      await cache.saveRawObj('profile:uid$i', {'name': 'User $i'});
    }
    await cache.saveRawObj('reactions:chat1', {
      'm1': {'❤️': ['u1']},
    });
    expect(cache.peekRawObj('reactions:chat1')['m1'], isNotNull);
  });

  test('bucket generik tetap dibatasi (eviction lama tidak hilang)', () async {
    for (var i = 0; i < 120; i++) {
      await cache.saveRawObj('profile:uid$i', {'name': 'User $i'});
    }
    // Entri paling awal sudah ter-evict dari memori bucket generik.
    expect(cache.peekRawObj('profile:uid0'), isEmpty);
    // Yang terbaru masih ada.
    expect(cache.peekRawObj('profile:uid119'), isNotEmpty);
  });
}
