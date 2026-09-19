import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chatyuk/core/cache/message_cache.dart';

/// Fokus: lapisan MEMORI list chat (centang-2 cepat).
/// `saveRawList` menyimpan ke memori lebih dulu, lalu disk (yang gagal di
/// test karena butuh Keystore — ditelan try/catch). `peekRawList` harus
/// sinkron & langsung terisi setelah save; inilah yang dipakai layar chat
/// untuk mengisi `_otherLastRead` tanpa hop async.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = MessageCache.instance;

  setUp(() {
    // clearAll menyentuh SharedPreferences (purge format lama) → butuh mock.
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => cache.clearAll());

  test('peekRawList sinkron: kosong sebelum, terisi sesudah save', () {
    const uid = 'uid-test-1';
    expect(cache.peekRawList(uid), isEmpty);

    final rows = [
      {
        'chatId': 'chat-1',
        'lastReadAt': {'other-uid': '2026-09-15T07:00:00.000Z'},
        'lastMessage': 'halo',
      },
    ];
    // Fire-and-forget: memori diisi SINKRON sebelum await disk.
    cache.saveRawList(uid, rows);

    final peek = cache.peekRawList(uid);
    expect(peek.length, 1);
    expect(peek.first['chatId'], 'chat-1');
  });

  test('peekRawList: uid tanpa snapshot = list kosong (bukan throw)', () {
    expect(cache.peekRawList('uid-tidak-ada'), isEmpty);
  });

  test('lastReadAt terbaca sebagai map ISO → parseable', () {
    const uid = 'uid-test-2';
    cache.saveRawList(uid, [
      {
        'chatId': 'chat-9',
        'lastReadAt': {'u-b': '2026-09-15T03:04:05.000Z'},
      },
    ]);
    final row = cache.peekRawList(uid).first;
    final raw = row['lastReadAt'] as Map;
    final t = DateTime.tryParse('${raw['u-b']}');
    expect(t, isNotNull);
    expect(t!.toUtc().hour, 3);
  });

  test('clearAll mengosongkan snapshot memori', () async {
    const uid = 'uid-test-3';
    cache.saveRawList(uid, [
      {'chatId': 'chat-x', 'lastReadAt': <String, dynamic>{}},
    ]);
    expect(cache.peekRawList(uid), isNotEmpty);
    await cache.clearAll();
    expect(cache.peekRawList(uid), isEmpty);
  });
}
