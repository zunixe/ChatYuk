import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/cache/media_disk_cache.dart';
import 'package:chatyuk/services/avatar_service.dart';

import 'supabase_test_client.dart';
import 'test_helper.dart';

/// Fase 3 — AvatarB64Service: cache RAM/disk & jalur get.
/// Logic-only: HTTP palsu; bagian download storage di-guard.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSupabaseHandler handler;
  late AvatarB64Service svc;

  setUp(() async {
    mockPathProvider();
    await MediaDiskCache.instance.clearAll();
    await MediaDiskCache.instance.prewarm();
    handler = FakeSupabaseHandler();
    svc = AvatarB64Service.forTest(fakeSupabaseClient(handler: handler));
  });

  test('get uid kosong → "" tanpa menyentuh network', () async {
    expect(await svc.get(''), '');
  });

  test('setForUid lalu get → cache hit (tanpa network)', () async {
    svc.setForUid('u1', 'QUJD');
    expect(await svc.get('u1'), 'QUJD');
    expect(handler.captured.isEmpty, isTrue);
  });

  test('clearForUid → cache dibuang', () async {
    svc.setForUid('u1', 'QUJD');
    svc.clearForUid('u1');
    // Setelah clear, get akan mencoba network (RPC avatar_for) → kosong.
    handler.on('avatar_for', (_) => '');
    expect(await svc.get('u1'), '');
  });

  test('get yang tidak ada di cache → ambil dari RPC avatar_for (kosong)',
      () async {
    handler.on('avatar_for', (_) => '');
    expect(await svc.get('u2'), '');
  });

  test('get profil avatar base64 → dikembalikan apa adanya', () async {
    handler.on('avatar_for', (_) => 'SGVsbG8=');
    expect(await svc.get('u3'), 'SGVsbG8=');
  });

  test('get dari DISK (tanpa network) memakai MediaDiskCache', () async {
    final bytes = Uint8List.fromList(utf8.encode('diskimg'));
    await MediaDiskCache.instance.write('avatars/u4.jpg', bytes);
    final out = await svc.get('u4');
    expect(out, base64Encode(bytes));
    // Tidak memanggil RPC avatar_for untuk uid ini.
    final rpcReqs = handler.captured
        .where((r) => r.url.path.contains('/rpc/avatar_for'))
        .toList();
    expect(rpcReqs, isEmpty);
  });

  test('clearForPath tidak crash untuk path tak dikenal', () {
    expect(() => svc.clearForPath('avatars/none.jpg'), returnsNormally);
  });

  test('prefetch uids kosong → no-op tanpa network', () async {
    await svc.prefetch([]);
    expect(handler.captured.isEmpty, isTrue);
  });

  test('prefetch mengambil batch dari RPC avatars_for', () async {
    handler.on('avatars_for', (_) => [
          {'id': 'a', 'avatar': 'QQ=='},
          {'id': 'b', 'avatar': 'Qg=='},
        ]);
    await svc.prefetch(['a', 'b']);
    expect(await svc.get('a'), 'QQ==');
    expect(await svc.get('b'), 'Qg==');
  });

  test('hasil kosong tidak dihafal — get kedua coba network lagi', () async {
    var calls = 0;
    handler.on('avatar_for', (_) {
      calls++;
      return calls == 1 ? '' : 'QUJD';
    });
    expect(await svc.get('u-empty'), '');
    expect(await svc.get('u-empty'), 'QUJD',
        reason: "'' gagal sesaat tidak boleh di-cache permanen");
    expect(calls, 2);
  });

  test('concurrent get uid sama berbagi 1 RPC (dedupe inflight)', () async {
    var calls = 0;
    handler.on('avatar_for', (_) {
      calls++;
      return 'QUJD';
    });
    final results = await Future.wait([svc.get('u-race'), svc.get('u-race')]);
    expect(results, ['QUJD', 'QUJD']);
    expect(calls, 1,
        reason: 'caller kedua menunggu job sama, bukan RPC kedua');
  });
}
