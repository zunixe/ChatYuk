import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/chat_stream_session.dart';

import 'supabase_test_client.dart';
import 'chat_stream_session_test.dart' show row;

/// REGRESI PERF (A1, 2026-10-11): `ChatStreamSession.revision` naik tiap isi
/// pesan berubah. UI (`_deriveItems`) memakai revisi sebagai kunci cache —
/// tanpa ini, `identical(msgsSrc)` selalu miss (stream emit list BARU tiap
/// event) → O(N) recompute tiap emit = "makin lama makin ngelag saat ngetik".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChatStreamSession mk(FakeSupabaseHandler h, String key) => ChatStreamSession(
        sb: fakeSupabaseClient(handler: h),
        cacheKey: key,
        needsPhotoFill: (_) => false,
        downloadVoiceToCache: (_, _) async {},
        prefetchVoiceBytes: (_) async {},
      );

  test('revision naik saat isi pesan berubah (emit stream)', () async {
    final h = FakeSupabaseHandler();
    h.on('/rest/v1/messages', (_) => [
          row(1, 'pertama', createdAt: '2026-01-01T00:00:01Z'),
        ]);

    final handle = mk(h, 'room_rev').start();
    final rev0 = handle.revision.value;
    await handle.stream.first.timeout(const Duration(seconds: 3));
    final rev1 = handle.revision.value;
    // Revisi WAJIB naik setelah emit isi pertama (bukan 0 → 0).
    expect(rev1, greaterThan(rev0));
  });

  test('revision TIDAK naik bila tak ada emit baru (cache derive HIT)', () async {
    final h = FakeSupabaseHandler();
    h.on('/rest/v1/messages', (_) => [
          row(1, 'x', createdAt: '2026-01-01T00:00:01Z'),
        ]);
    final handle = mk(h, 'room_rev2').start();
    await handle.stream.first.timeout(const Duration(seconds: 3));
    final revA = handle.revision.value;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final revB = handle.revision.value;
    // Tanpa event baru, revisi stabil (cache _deriveItems tetap HIT).
    expect(revB, revA);
  });
}
