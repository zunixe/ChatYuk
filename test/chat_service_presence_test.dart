import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/chat_service.dart';

import 'supabase_test_client.dart';

/// Fase 3 — ChatService presence: logika status murni + last_seen (RPC).
/// Logic-only: tidak menyentuh realtime WebSocket.
void main() {
  group('effectiveStatusOf (murni)', () {
    String fresh() => DateTime.now().toUtc().toIso8601String();
    String stale() => DateTime.now()
        .toUtc()
        .subtract(const Duration(minutes: 40))
        .toIso8601String();

    test('null status → offline', () {
      expect(ChatService.effectiveStatusOf(null, fresh()), 'offline');
    });

    test('status offline / invisible → selalu offline', () {
      expect(ChatService.effectiveStatusOf('offline', fresh()), 'offline');
      expect(ChatService.effectiveStatusOf('invisible', fresh()), 'offline');
    });

    test('online + last_seen segar → online', () {
      expect(ChatService.effectiveStatusOf('online', fresh()), 'online');
    });

    test('online tapi last_seen basi (>30m) → offline', () {
      expect(ChatService.effectiveStatusOf('online', stale()), 'offline');
    });

    test('idle + segar → idle', () {
      expect(ChatService.effectiveStatusOf('idle', fresh()), 'idle');
    });

    test('last_seen tidak valid → offline', () {
      expect(
        ChatService.effectiveStatusOf('online', 'bukan-tanggal'),
        'offline',
      );
      expect(ChatService.effectiveStatusOf('online', null), 'offline');
    });
  });

  group('shouldDropOnlineUid / isVisibleOnlineStatus (murni)', () {
    test('shouldDrop: offline & invisible → true', () {
      expect(ChatService.shouldDropOnlineUid('offline'), isTrue);
      expect(ChatService.shouldDropOnlineUid('invisible'), isTrue);
    });

    test('shouldDrop: online/idle/null → false', () {
      expect(ChatService.shouldDropOnlineUid('online'), isFalse);
      expect(ChatService.shouldDropOnlineUid('idle'), isFalse);
      expect(ChatService.shouldDropOnlineUid(null), isFalse);
    });

    test('isVisibleOnlineStatus: hanya online/idle', () {
      expect(ChatService.isVisibleOnlineStatus('online'), isTrue);
      expect(ChatService.isVisibleOnlineStatus('idle'), isTrue);
      expect(ChatService.isVisibleOnlineStatus('offline'), isFalse);
      expect(ChatService.isVisibleOnlineStatus('invisible'), isFalse);
      expect(ChatService.isVisibleOnlineStatus(null), isFalse);
    });
  });

  group('getUserLastSeen (HTTP palsu)', () {
    late FakeSupabaseHandler handler;
    late ChatService svc;

    setUp(() {
      handler = FakeSupabaseHandler();
      svc = ChatService(fakeSupabaseClient(handler: handler));
    });

    test('uid kosong → null tanpa network', () async {
      expect(await svc.getUserLastSeen(''), isNull);
      expect(handler.captured.isEmpty, isTrue);
    });

    test('last_seen valid → DateTime (via RPC presence_for)', () async {
      handler.on(
        'presence_for',
        (_) => [
          {'status': 'online', 'last_seen': '2026-01-01T00:00:00.000Z'},
        ],
      );
      final out = await svc.getUserLastSeen('u1');
      expect(out, isNotNull);
      expect(out!.toUtc().year, 2026);
    });

    test('last_seen null → null', () async {
      handler.on(
        'presence_for',
        (_) => [
          {'status': 'online', 'last_seen': null},
        ],
      );
      expect(await svc.getUserLastSeen('u1'), isNull);
    });

    test('hasil RPC kosong → null', () async {
      handler.on('presence_for', (_) => []);
      expect(await svc.getUserLastSeen('u1'), isNull);
    });

    test('error → null (tidak crash)', () async {
      final h = FakeSupabaseHandler()
        ..on('presence_for', (_) => throw Exception('x'));
      final s = ChatService(fakeSupabaseClient(handler: h));
      expect(await s.getUserLastSeen('u1'), isNull);
    });
  });

  group('getUserStatus — initialStatus (emit langsung, tanpa fetch)', () {
    // initialStatus != null → stream emit status awal tanpa memanggil RPC
    // presence_for / WebSocket, sehingga bisa diuji deterministik.
    ChatService svc() => ChatService(fakeSupabaseClient());

    test('initialStatus online → emit "online" segera', () async {
      final stream = svc().getUserStatus('u1', initialStatus: 'online');
      final first = await stream.first.timeout(const Duration(seconds: 2));
      expect(first, 'online');
    });

    test('initialStatus idle → emit "idle"', () async {
      final stream = svc().getUserStatus('u1', initialStatus: 'idle');
      expect(await stream.first.timeout(const Duration(seconds: 2)), 'idle');
    });

    test('initialStatus offline → tidak emit apa pun (senyap)', () async {
      final stream = svc().getUserStatus('u1', initialStatus: 'offline');
      // Status offline awal tidak di-emit; pastikan tidak ada event cepat.
      var emitted = false;
      final sub = stream.listen((_) => emitted = true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emitted, isFalse);
      await sub.cancel();
    });
  });
}
