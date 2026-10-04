import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/chat_stream_session.dart';

import 'supabase_test_client.dart';
import 'test_helper.dart';

Map<String, dynamic> row(
  int id,
  String text, {
  String createdAt = '2026-01-01T00:00:00Z',
  bool deleted = false,
}) =>
    {
      'id': id,
      'sender_id': 'u2',
      'sender_name': 'Budi',
      'sender_gender': 'male',
      'text': text,
      'type': 'text',
      'is_registered': true,
      'created_at': createdAt,
      'is_deleted': deleted,
      'edited': false,
      'image_path': '',
      'voice_path': '',
      'duration_ms': 0,
    };

/// Sesi stream pesan tanpa realtime: fetch, merge, pagination, poll.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
  });

  // NOTE: cacheKey UNIK per test — MessageCache memory singleton bertahan
  // antar test dalam satu file (secure storage absen di test env).
  ChatStreamSession session(FakeSupabaseHandler handler, String key) =>
      ChatStreamSession(
        sb: fakeSupabaseClient(handler: handler),
        cacheKey: key,
        needsPhotoFill: (_) => false,
        downloadVoiceToCache: (_, __) async {},
        prefetchVoiceBytes: (_) async {},
      );

  group('fetch + merge', () {
    test('pesan terurut menaik + terhapus dibersihkan', () async {
      final handler = FakeSupabaseHandler();
      // Server selalu DESC (order created_at desc) — merge mengandalkan itu.
      handler.on('/rest/v1/messages', (_) => [
            row(3, 'rahasia', createdAt: '2026-01-01T00:00:03Z', deleted: true),
            row(2, 'kedua', createdAt: '2026-01-01T00:00:02Z'),
            row(1, 'pertama', createdAt: '2026-01-01T00:00:01Z'),
          ]);

      final handle = session(handler, 'room_merge').start();
      final list = await handle.stream.first.timeout(
        const Duration(seconds: 3),
      );

      expect(list.map((m) => m.text), ['pertama', 'kedua', '']);
      expect(list.last.isDeleted, isTrue);
    });

    test('reload ulang → tanpa duplikat', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/messages', (_) => [
            row(2, 'dua', createdAt: '2026-01-01T00:00:02Z'),
            row(1, 'satu', createdAt: '2026-01-01T00:00:01Z'),
          ]);

      final handle = session(handler, 'room_dedup').start();
      var list = await handle.stream.first.timeout(
        const Duration(seconds: 3),
      );
      expect(list.length, 2);

      final next = handle.stream.first;
      await handle.reload();
      list = await next.timeout(const Duration(seconds: 3));
      expect(list.map((m) => m.text), ['satu', 'dua']);
    });
  });

  group('loadOlder', () {
    test('pesan lama disisip di depan', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/messages', (req) {
        // Query paginasi memakai filter lt(created_at).
        if (req.url.query.contains('created_at=lt.')) {
          return [row(0, 'lama', createdAt: '2025-12-31T23:59:59Z')];
        }
        return [row(1, 'baru', createdAt: '2026-01-01T00:00:01Z')];
      });

      final handle = session(handler, 'room_older').start();
      var list = await handle.stream.first.timeout(
        const Duration(seconds: 3),
      );
      expect(list.map((m) => m.text), ['baru']);

      // firstWhere (bukan first): replay onListen bisa datang duluan.
      final found = handle.stream.firstWhere(
        (l) => l.any((m) => m.text == 'lama'),
      );
      await handle.loadOlder();
      list = await found.timeout(const Duration(seconds: 3));
      expect(list.map((m) => m.text), ['lama', 'baru']);
    });

    test('list DIBATASI 300 pesan (anti-tumbuh tak terbatas = lag)', () async {
      final handler = FakeSupabaseHandler();
      // Setiap paginasi (filter lt created_at) kembalikan 100 pesan lebih tua.
      // Fetch awal = 100 terbaru → setelah 4× loadOlder total 500 → dipangkas
      // jadi 300 (pertahankan yang TERBARU/terdekat viewport).
      var page = 0;
      int oldestFetched = 100000;
      handler.on('/rest/v1/messages', (req) {
        if (req.url.query.contains('created_at=lt.')) {
          final base = DateTime.utc(2026, 1, 1);
          final start = oldestFetched - 100 * (page + 1);
          return [
            for (var i = 0; i < 100; i++)
              row(
                start + i,
                'old${start + i}',
                createdAt: base
                    .add(Duration(minutes: start + i - 100000))
                    .toIso8601String(),
              ),
          ];
        }
        final base = DateTime.utc(2026, 1, 1);
        return [
          for (var i = 0; i < 100; i++)
            row(
              99900 + i,
              'new$i',
              createdAt: base
                  .add(Duration(minutes: i))
                  .toIso8601String(),
            ),
        ];
      });

      final handle = session(handler, 'room_cap').start();
      var list = await handle.stream.first.timeout(const Duration(seconds: 3));
      expect(list.length, 100);

      // Tambah pesan lama berulang → melewati cap.
      for (var k = 0; k < 5; k++) {
        oldestFetched -= 100;
        page = k;
        final bigger = handle.stream.firstWhere(
          (l) => l.length > list.length || l.length == 300,
        );
        await handle.loadOlder();
        list = await bigger.timeout(const Duration(seconds: 3));
      }
      // Tidak boleh melebihi cap.
      expect(list.length, lessThanOrEqualTo(300),
          reason: 'list pesan harus dibatasi (anti tumbuh tak terbatas)');
    });
  });

  // NOTE: timer poll 30 dtk & callback realtime tidak diuji di sini —
  // butuh event-loop asli (platform channel cache), fakeAsync menggantung
  // fetch (lihat supabase_test_client.dart). reload() yang dipakai poll
  // sudah dikunci di atas.
}
