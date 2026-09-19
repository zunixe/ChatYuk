import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/chat_stream_session.dart';

import '../supabase_test_client.dart';
import '../test_helper.dart';

/// REGRESSION (docs/FEATURE_MAP.md §3a):
/// Stream broadcast tidak menyimpan emit terakhir. `ChatStreamSession`
/// membuat stream di `initState` SEBELUM `StreamBuilder` subscribe; tanpa
/// `controller.onListen` yang meng-emit ulang `_current`, emit memori HILANG
/// → chat tampil kosong dulu ("loading pesan").
///
/// Kontrak yang dikunci: listener yang datang BELAKANGAN tetap menerima
/// snapshot terakhir (replay), bukan menunggu event baru.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initSupabaseForTest();
  });

  ChatStreamSession session(FakeSupabaseHandler handler) => ChatStreamSession(
        sb: fakeSupabaseClient(handler: handler),
        cacheKey: 'room_r1',
        needsPhotoFill: (_) => false,
        downloadVoiceToCache: (_, __) async {},
        prefetchVoiceBytes: (_) async {},
      );

  test('listener yang subscribe terlambat tetap dapat snapshot', () async {
    final handler = FakeSupabaseHandler();
    handler.on('/rest/v1/messages', (_) => [
          {
            'id': 1,
            'sender_id': 'u2',
            'sender_name': 'Budi',
            'sender_gender': 'male',
            'text': 'pesan lama',
            'type': 'text',
            'is_registered': true,
            'created_at': '2026-01-01T00:00:00Z',
            'is_deleted': false,
            'edited': false,
            'image_path': '',
            'voice_path': '',
            'duration_ms': 0,
          }
        ]);

    final handle = session(handler).start();
    // Beri waktu reload() menyelesaikan fetch pertama (tanpa listener).
    await Future<void>.delayed(const Duration(milliseconds: 250));

    // Subscribe BARU (terlambat) — inilah skenario StreamBuilder mount belakangan.
    final first = await handle.stream.first.timeout(
      const Duration(seconds: 3),
      onTimeout: () => throw StateError(
        'REPLAY GAGAL: listener terlambat tidak menerima snapshot mana pun',
      ),
    );
    expect(first, isNotEmpty, reason: 'snapshot harus di-replay');
    expect(first.first.text, 'pesan lama');
  });

  test('snapshot berisi SEMUA pesan (bukan sebagian) saat di-replay',
      () async {
    final handler = FakeSupabaseHandler();
    handler.on('/rest/v1/messages', (_) => [
          {
            'id': 2,
            'sender_id': 'u3',
            'sender_name': 'Sari',
            'sender_gender': 'female',
            'text': 'satu',
            'type': 'text',
            'is_registered': true,
            'created_at': '2026-01-01T00:00:01Z',
            'is_deleted': false,
            'edited': false,
            'image_path': '',
            'voice_path': '',
            'duration_ms': 0,
          },
          {
            'id': 3,
            'sender_id': 'u3',
            'sender_name': 'Sari',
            'sender_gender': 'female',
            'text': 'dua',
            'type': 'text',
            'is_registered': true,
            'created_at': '2026-01-01T00:00:02Z',
            'is_deleted': false,
            'edited': false,
            'image_path': '',
            'voice_path': '',
            'duration_ms': 0,
          }
        ]);

    final handle = session(handler).start();
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final snapshot = await handle.stream.first.timeout(
      const Duration(seconds: 3),
    );
    // Replay bisa datang dari emit memori lalu server — inti regresinya:
    // listener TERLAMBAT tetap menerima snapshot, bukan menunggu event baru.
    expect(snapshot, isNotEmpty, reason: 'snapshot harus di-replay');
    expect(snapshot.map((m) => m.id), containsAll(['2', '3']));
  });
}
