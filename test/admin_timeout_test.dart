import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:chatyuk/services/admin_service.dart';
import 'package:chatyuk/services/storage_photo_service.dart';

import 'supabase_test_client.dart';

/// Regresi kasus nyata (monitor chat 9436): koneksi stall membuat RPC /
// download foto tidak pernah selesai → spinner selamanya ("blank"/"hang").
// Kontrak yang dikunci di sini:
// - RPC jalur buka panel: gagal-cepat via TimeoutException (≤30 dtk),
//   provider memetakan ke banner error + tombol ulangi.
// - Download storage: gagal-cepat via null (kontrak lama dipertahankan).
void main() {
  group('admin RPC timeout (jalur buka panel)', () {
    test('getStats hang → TimeoutException', () {
      fakeAsync((async) {
        final handler = FakeSupabaseHandler();
        handler.onHang('admin_stats');
        final svc = AdminService(fakeSupabaseClient(handler: handler));
        Object? err;
        svc.getStats().then<void>((_) {}, onError: (Object e) { err = e; });
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(err, isA<TimeoutException>());
      });
    });

    test('getStatsForce hang → TimeoutException', () {
      fakeAsync((async) {
        final handler = FakeSupabaseHandler();
        handler.onHang('admin_stats_force');
        final svc = AdminService(fakeSupabaseClient(handler: handler));
        Object? err;
        svc.getStatsForce().then<void>((_) {}, onError: (Object e) { err = e; });
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(err, isA<TimeoutException>());
      });
    });

    test('getStatsDetail hang → TimeoutException', () {
      fakeAsync((async) {
        final handler = FakeSupabaseHandler();
        handler.onHang('admin_stats_detail');
        final svc = AdminService(fakeSupabaseClient(handler: handler));
        Object? err;
        svc.getStatsDetail().then<void>((_) {}, onError: (Object e) { err = e; });
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(err, isA<TimeoutException>());
      });
    });

    test('getPointSettings hang → TimeoutException', () {
      fakeAsync((async) {
        final handler = FakeSupabaseHandler();
        handler.onHang('admin_get_point_settings');
        final svc = AdminService(fakeSupabaseClient(handler: handler));
        Object? err;
        svc.getPointSettings().then<void>((_) {}, onError: (Object e) { err = e; });
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(err, isA<TimeoutException>());
      });
    });

    test('listDevices hang → TimeoutException', () {
      fakeAsync((async) {
        final handler = FakeSupabaseHandler();
        handler.onHang('admin_list_devices');
        final svc = AdminService(fakeSupabaseClient(handler: handler));
        Object? err;
        svc.listDevices().then<void>((_) {}, onError: (Object e) { err = e; });
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(err, isA<TimeoutException>());
      });
    });

    test('getMessageImage hang → TimeoutException (foto bisa retry)', () {
      fakeAsync((async) {
        final handler = FakeSupabaseHandler();
        handler.onHang('admin_get_message_image');
        final svc = AdminService(fakeSupabaseClient(handler: handler));
        Object? err;
        svc.getMessageImage(9436).then<void>((_) {}, onError: (Object e) { err = e; });
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(err, isA<TimeoutException>());
      });
    });

    test('getMessageImage sukses → path diteruskan apa adanya', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        'admin_get_message_image',
        (_) => 'chat/abc/123.jpg',
      );
      final svc = AdminService(fakeSupabaseClient(handler: handler));
      expect(await svc.getMessageImage(9436), 'chat/abc/123.jpg');
    });

    test('panggilan berikutnya tetap bisa sukses (tidak keracunan)', () async {
      final handler = FakeSupabaseHandler();
      handler.on('admin_stats', (_) => {'users': 7});
      final svc = AdminService(fakeSupabaseClient(handler: handler));
      expect((await svc.getStats())['users'], 7);
    });
  });

  group('download storage timeout', () {
    test('hang → null (kontrak gagal-cepat dipertahankan)', () {
      fakeAsync((async) {
        final handler = FakeSupabaseHandler();
        handler.onHang('storage');
        final svc = StoragePhotoService.forTest(
          fakeSupabaseClient(handler: handler),
        );
        Object? result = 'belum';
        svc.download('chat/abc/123.jpg').then((v) => result = v);
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(result, isNull);
      });
    });

    test('sukses → base64 isi file', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        'storage',
        (_) => http.Response(
          'ABC',
          200,
          headers: {'content-type': 'image/jpeg'},
        ),
      );
      final svc = StoragePhotoService.forTest(
        fakeSupabaseClient(handler: handler),
      );
      // base64("ABC") == "QUJD".
      expect(await svc.download('chat/abc/123.jpg'), 'QUJD');
    });
  });
}
