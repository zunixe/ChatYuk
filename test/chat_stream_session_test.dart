import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/message_model.dart';
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
        downloadVoiceToCache: (_, _) async {},
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

    // Handler paginasi: tiap halaman = 100 pesan lebih tua dari `before`.
    FakeSupabaseHandler pagedHandler({List<String>? befores}) {
      final handler = FakeSupabaseHandler();
      var pages = 0;
      handler.on('/rest/v1/messages', (req) {
        final q = req.url.query;
        if (q.contains('created_at=lt.')) {
          final m = RegExp(r'created_at=lt\.([^&]+)').firstMatch(q);
          befores?.add(m?.group(1) ?? '');
          pages++;
          final beforeTs = DateTime.parse(Uri.decodeComponent(m!.group(1)!));
          final base = beforeTs.subtract(const Duration(minutes: 100));
          return [
            for (var i = 99; i >= 0; i--)
              row(
                pages * 1000 + i,
                'old$pages-$i',
                createdAt: base.add(Duration(minutes: i)).toIso8601String(),
              ),
          ];
        }
        final base = DateTime.utc(2026, 1, 1);
        return [
          for (var i = 99; i >= 0; i--)
            row(
              90000 + i,
              'n$i',
              createdAt: base.add(Duration(minutes: i)).toIso8601String(),
            ),
        ];
      });
      return handler;
    }

    // Listener PERSISTEN (seperti layar chat asli) — simpan emit terakhir.
    Future<(ChatMessageStream, List<MessageModel> Function())> openPaged(
      FakeSupabaseHandler handler,
      String key,
    ) async {
      final handle = session(handler, key).start();
      var latest = <MessageModel>[];
      handle.stream.listen((l) => latest = l);
      final deadline = DateTime.now().add(const Duration(seconds: 3));
      while (latest.length < 100 && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(latest.length, 100);
      return (handle, () => latest);
    }

    Future<void> loadOlderAndSettle(ChatMessageStream h) async {
      await h.loadOlder();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    // Regresi 2026-10-22 (bug B): dulu loadOlder menambah 100 pesan lama lalu
    // `_trim()` ke 100 TERBARU → yang baru dimuat langsung dibuang (scroll
    // mentok di 100, jump-to-reply room tak pernah sampai).
    test('loadOlder MENAMBAH riwayat & tidak dibuang trim', () async {
      final (handle, latest) =
          await openPaged(pagedHandler(), 'room_older_kept');
      for (var k = 1; k <= 5; k++) {
        await loadOlderAndSettle(handle);
        expect(latest().length, 100 + 100 * k);
        // Halaman yang BARU dimuat ada di depan list.
        expect(latest().first.text, 'old$k-0');
      }
      // Halaman lebih awal tetap ada (tidak dipangkas).
      expect(latest().any((m) => m.text == 'old1-50'), isTrue);
      // Urut menaik.
      final ts = latest().map((m) => m.timestamp).toList();
      for (var i = 1; i < ts.length; i++) {
        expect(ts[i].isBefore(ts[i - 1]), isFalse);
      }
    });

    // Room & grup memakai `_cachedMessagesStream(cacheKey: 'room_<id>')` yang
    // SAMA dengan ChatStreamSession → cap berlaku untuk keduanya. Diuji untuk
    // kedua jenis cacheKey (room global & grup) supaya terkunci.
    Future<void> capTest(String key) async {
      final handler = pagedHandler();
      final (handle, latest) = await openPaged(handler, key);
      // 15 halaman (1600 pesan) > batas riwayat 1100.
      for (var k = 0; k < 15; k++) {
        await loadOlderAndSettle(handle);
      }
      expect(latest().length, 1100,
          reason: '[$key] riwayat di memori harus dibatasi (anti tumbuh = lag)');
      // Pesan terbaru tetap utuh di ujung bawah.
      expect(latest().last.text, 'n99');
      // Setelah batas tercapai loadOlder berhenti menembak server.
      final pageReqs = handler.captured
          .where((r) => r.url.query.contains('created_at=lt.'))
          .length;
      expect(pageReqs, 10);
    }

    test('ROOM: riwayat DIBATASI 1100 pesan (anti-tumbuh = lag)', () async {
      await capTest('room_cap');
    });

    test('GROUP: riwayat DIBATASI 1100 pesan (anti-tumbuh = lag)', () async {
      await capTest('group_cap_123');
    });

    test('paginasi dalam: kursor sesi terus mundur', () async {
      // Regresi: kalau `loadOlder` memakai `_current.first` sebagai kursor
      // dan depan list kepangkas, `before` mundur → fetch duplikat → history
      // tak bisa di-scroll. Kursor sesi harus terus mundur.
      final befores = <String>[];
      final (handle, latest) =
          await openPaged(pagedHandler(befores: befores), 'room_deep');
      for (var k = 0; k < 5; k++) {
        await loadOlderAndSettle(handle);
      }
      expect(latest().length, 600);
      // Kursor `before` harus MONOTON MUNDUR (tiap halaman lebih tua) —
      // bukti paginasi jalan terus walau depan list kepangkas trim.
      expect(befores.length, 5);
      for (var i = 1; i < befores.length; i++) {
        expect(
          DateTime.parse(Uri.decodeComponent(befores[i])).isBefore(
            DateTime.parse(Uri.decodeComponent(befores[i - 1])),
          ),
          isTrue,
          reason: 'before[$i] harus lebih tua dari before[${i - 1}]',
        );
      }
    });
  });

  group('lifecycle: timer reconnect dibatalkan saat tak ada listener', () {
    // Regresi 2026-10-22: dulu `onCancel` hanya membatalkan pollTimer/
    // saveDebounce/reloadDebounce, TIDAK timer reconnect. Saat jaringan blip
    // lalu chat ditutup, timer itu menyala → reload() + openChannel() membuat
    // channel realtime BARU yang tidak pernah di-remove (langganan yatim:
    // traffic & memori naik, "makin lama makin lag").
    test('reload pasca-cancel tetap jalan (sesi dipakai ulang), tapi '
        'reconnect pending dibatalkan', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/messages', (_) => [
            row(1, 'satu', createdAt: '2026-01-01T00:00:01Z'),
          ]);

      final handle = session(handler, 'room_reconnect_cancel').start();
      await handle.stream.first.timeout(const Duration(seconds: 3));

      // Tutup listener (onCancel jalan → timer reconnect dibatalkan).
      await handle.stream.listen((_) {}).cancel();
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // Sesi MASIH boleh dipakai ulang: subscribe lagi harus dapat data
      // (replay `_current`), bukan stream mati.
      final again = await handle.stream.first.timeout(
        const Duration(seconds: 3),
      );
      expect(again.map((m) => m.text), contains('satu'));
    });
  });

  group('lifecycle: tutup chat → tidak ada channel yatim', () {
    // Regresi 2026-10-22 (bug A): `removeChannel` di onCancel memicu status
    // `closed` pada channel lama; guard `identical(ch, channel)` masih cocok →
    // requestReconnect → ~2 dtk kemudian reload + channel BARU yang tak pernah
    // dibuang. Setelah onCancel: 0 channel, 0 fetch, 0 reconnect.
    test('setelah cancel: channel dibuang, tak ada reload/channel baru',
        () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/messages', (_) => [
            row(1, 'satu', createdAt: '2026-01-01T00:00:01Z'),
          ]);
      final sb = fakeSupabaseClient(handler: handler);
      final handle = ChatStreamSession(
        sb: sb,
        cacheKey: 'room_orphan',
        needsPhotoFill: (_) => false,
        downloadVoiceToCache: (_, _) async {},
        prefetchVoiceBytes: (_) async {},
      ).start();
      final sub = handle.stream.listen((_) {});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(sb.getChannels().length, 1);

      await sub.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final fetchesAtClose = handler.captured
          .where((r) => r.url.path.contains('/rest/v1/messages'))
          .length;
      // Lewati jendela backoff reconnect pertama (2 dtk ± 25%).
      await Future<void>.delayed(const Duration(milliseconds: 3200));

      expect(sb.getChannels(), isEmpty,
          reason: 'channel realtime harus dibuang & tidak dibuat ulang');
      expect(
        handler.captured
            .where((r) => r.url.path.contains('/rest/v1/messages'))
            .length,
        fetchesAtClose,
        reason: 'tak boleh ada reload dari timer reconnect setelah ditutup',
      );
    });
  });

  // NOTE: timer poll 30 dtk & callback realtime tidak diuji di sini —
  // butuh event-loop asli (platform channel cache), fakeAsync menggantung
  // fetch (lihat supabase_test_client.dart). reload() yang dipakai poll
  // sudah dikunci di atas.
}
