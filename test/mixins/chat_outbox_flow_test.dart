import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:chatyuk/core/cache/message_cache.dart';
import 'package:chatyuk/core/cache/message_store.dart';
import 'package:chatyuk/core/cache/offline_outbox.dart';
import 'package:chatyuk/mixins/chat_outbox_mixin.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/models/auth_data.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/services/points_service.dart';

class MockPointsService extends Mock implements PointsService {}

class _TestAuth extends AuthNotifier {
  _TestAuth() : super(autoInit: false);
  @override
  AuthData build() => const AuthData(uid: 'u-me', loading: false);
  @override
  String? get uid => 'u-me';
  @override
  UserModel? get profile => null;
}

class TestPoints extends PointsNotifier {
  final int deductResult;
  TestPoints({this.deductResult = 50}) : super(service: MockPointsService());
  int deductCalls = 0;
  int refundCalls = 0;
  @override
  PointsState build() => const PointsState();
  @override
  Future<int> deductBeforeSend(String _) async {
    deductCalls++;
    return deductResult;
  }

  @override
  Future<void> refundChatPoint(String _) async => refundCalls++;
}

/// Harness `ChatOutboxMixin` — mengunci antrean offline (AGENTS.md: modul
/// bersama private ↔ room; dulu disalin-tempel dan mulai divergen).
class OutboxHost extends StatefulWidget {
  const OutboxHost({super.key, this.online = true, this.sendThrows = false});
  final bool online;
  final bool sendThrows;
  @override
  State<OutboxHost> createState() => OutboxHostState();
}

class OutboxHostState extends State<OutboxHost> with ChatOutboxMixin<OutboxHost> {
  final List<MessageModel> pendingList = [];
  final Set<String> queued = {};
  bool flushing = false;
  final List<String> sentOrder = [];
  int onSentCount = 0;
  int scrollCount = 0;
  Object? sendError;

  @override
  String get outboxKind => 'private';
  @override
  String get outboxChatId => 'chat_1';
  @override
  String get outboxUploadChatId => 'chat_1';
  @override
  List<MessageModel> get outboxPending => pendingList;
  @override
  Set<String> get outboxQueuedIds => queued;
  @override
  bool get outboxIsFlushing => flushing;
  @override
  set outboxIsFlushing(bool v) => flushing = v;
  @override
  bool get outboxIsOnline => widget.online;
  @override
  void outboxScrollToBottom() => scrollCount++;
  @override
  Future<void> outboxSendEntry(OutboxEntry e, String imageData) async {
    if (widget.sendThrows) throw Exception('bukan error jaringan');
    if (sendError != null) throw sendError!;
    sentOrder.add(e.pendingId);
  }

  @override
  void outboxOnSent() => onSentCount++;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

MessageModel pendingMsg(String id, {String text = 'halo'}) => MessageModel(
      id: id,
      senderId: 'u-me',
      senderName: 'Me',
      senderGender: 'male',
      isRegistered: true,
      text: text,
      type: 'text',
      imageData: '',
      timestamp: DateTime.now(),
    );

Future<OutboxHostState> pumpOutbox(
  WidgetTester tester, {
  bool online = true,
  bool sendThrows = false,
  int deductResult = 50,
  TestPoints? points,
}) async {
  final svc = MockPointsService();
  when(() => svc.deductChatPoint(any())).thenAnswer((_) async => deductResult);
  when(() => svc.refundChatPoint(any())).thenAnswer((_) async => 55);
  when(() => svc.watchOwnPoints()).thenAnswer((_) => const Stream.empty());
  when(() => svc.getWallet()).thenAnswer(
    (_) async => <String, dynamic>{'bonus': 0, 'earned': 0, 'total': 50},
  );

  final container = ProviderContainer(
    overrides: [
      pointsProvider.overrideWith(
        () => points ?? TestPoints(deductResult: deductResult),
      ),
      authProvider.overrideWith(_TestAuth.new),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: OutboxHost(online: online, sendThrows: sendThrows),
        ),
      ),
    ),
  );
  final state = tester.state<OutboxHostState>(find.byType(OutboxHost));
  // Buang widget → Provider men-dispose PointsProvider (mematikan timer 30s).
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // OfflineOutbox mempersist ke MessageStore (SQLite) → butuh ffi + DB nyata.
  // Test I/O memakai `test()` (bukan `testWidgets`) karena `testWidgets`
  // memakai FakeAsync sehingga file I/O nyata tak pernah selesai (hang).
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('outbox_test');
    MessageStore.debugDir = dir.path;
    MessageStore.debugOpener = (path) => databaseFactory.openDatabase(path);
    await MessageStore.instance.open('test');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MessageCache.instance.clearAll();
    await OfflineOutbox.instance.load();
    for (final e in OfflineOutbox.instance.all) {
      await OfflineOutbox.instance.remove(e.pendingId);
    }
  });

  group('ChatOutboxMixin — queueOffline (I/O)', () {
    test('menyimpan ke antrean + field penting utuh', () async {
      SharedPreferences.setMockInitialValues({});
      await OfflineOutbox.instance.enqueue(
        OutboxEntry(
          pendingId: 'p1',
          kind: 'private',
          chatId: 'chat_1',
          senderId: 'u-me',
          senderName: 'Me',
          senderGender: 'male',
          text: 'halo',
          createdAt: DateTime.now(),
          pointsDeducted: true,
          pointsKind: 'text',
          repliedToId: 'm9',
          repliedToText: 'pesan lama',
          repliedToSenderName: 'Budi',
          isForwarded: true,
        ),
      );
      final e = OfflineOutbox.instance.forChat('private', 'chat_1').single;
      expect(e.text, 'halo');
      expect(e.pointsDeducted, isTrue);
      expect(e.repliedToId, 'm9');
      expect(e.repliedToText, 'pesan lama');
      expect(e.repliedToSenderName, 'Budi');
      expect(e.isForwarded, isTrue);
    });
  });

  group('ChatOutboxMixin — flushOutbox (widget)', () {
    testWidgets('offline → flush TIDAK mengirim apa pun', (tester) async {
      final s = await pumpOutbox(tester, online: false);
      s.queued.add('stub');
      await s.flushOutbox();
      await tester.pump();
      expect(s.sentOrder, isEmpty);
      expect(s.onSentCount, 0);
    });

    testWidgets('antrean kosong → tidak ada aksi', (tester) async {
      final s = await pumpOutbox(tester);
      await s.flushOutbox();
      await tester.pump();
      expect(s.sentOrder, isEmpty);
      expect(s.scrollCount, 0);
    });

    testWidgets('guard: flush saat sudah flushing → tidak dobel',
        (tester) async {
      final s = await pumpOutbox(tester);
      s.flushing = true;
      await s.flushOutbox();
      await tester.pump();
      expect(s.sentOrder, isEmpty, reason: 'flush kedua harus diabaikan');
      expect(s.flushing, isTrue, reason: 'tidak menimpa flag milik flush aktif');
    });
  });

  group('ChatOutboxMixin — flushOutbox poin (I/O nyata)', () {
    OutboxEntry entry(String id) => OutboxEntry(
          pendingId: id,
          kind: 'private',
          chatId: 'chat_1',
          senderId: 'u-me',
          senderName: 'Me',
          senderGender: 'male',
          text: '[TEST] halo',
          createdAt: DateTime.now(),
          pointsKind: 'text',
        );

    testWidgets('deduct sukses + error jaringan → flush kedua TIDAK memotong lagi',
        (tester) async {
      final points = TestPoints();
      final s = await pumpOutbox(tester, points: points);
      s.sendError = const SocketException('offline');
      await tester.runAsync(() async {
        await OfflineOutbox.instance.enqueue(entry('p-net'));
        await s.flushOutbox();
      });
      expect(points.deductCalls, 1);
      final kept = OfflineOutbox.instance.forChat('private', 'chat_1').single;
      expect(kept.pointsDeducted, isTrue,
          reason: 'flag poin wajib tersimpan sebelum kirim');

      await tester.runAsync(() => s.flushOutbox());
      expect(points.deductCalls, 1, reason: 'poin tidak boleh terpotong dua kali');
      expect(points.refundCalls, 0);

      s.sendError = null;
      await tester.runAsync(() => s.flushOutbox());
      await tester.pump();
      expect(points.deductCalls, 1);
      expect(s.sentOrder, ['p-net']);
      expect(OfflineOutbox.instance.forChat('private', 'chat_1'), isEmpty);
    });

    testWidgets('deduct sukses + error non-jaringan → refund + entri dibuang',
        (tester) async {
      final points = TestPoints();
      final s = await pumpOutbox(tester, points: points);
      s.sendError = Exception('bukan error jaringan');
      s.pendingList.add(pendingMsg('p-bad'));
      await tester.runAsync(() async {
        await OfflineOutbox.instance.enqueue(entry('p-bad'));
        await s.flushOutbox();
      });
      await tester.pump();
      expect(points.deductCalls, 1);
      expect(points.refundCalls, 1, reason: 'poin yang sudah dipotong wajib di-refund');
      expect(OfflineOutbox.instance.forChat('private', 'chat_1'), isEmpty);
      expect(s.pendingList, isEmpty);
    });
  });

  // BLOKIR SENYAP (2026-10-23): pesan yang ditolak karena blokir TETAP tampil
  // centang-1 lintas buka-tutup chat & TIDAK PERNAH dikirim ulang.
  group('ChatOutboxMixin — blokir (I/O nyata)', () {
    final blockedErr = Exception(
      'PostgrestException(message: blocked, code: P0001, details: null)',
    );
    OutboxEntry entry(String id) => OutboxEntry(
          pendingId: id,
          kind: 'private',
          chatId: 'chat_1',
          senderId: 'u-me',
          senderName: 'Me',
          senderGender: 'male',
          text: '[TEST] diblokir',
          createdAt: DateTime.now(),
          pointsKind: 'text',
        );

    testWidgets('keepBlocked: bubble tetap, bukan antrean kirim, tersimpan',
        (tester) async {
      final s = await pumpOutbox(tester);
      final m = pendingMsg('p-blk');
      s.pendingList.add(m);
      await tester.runAsync(() => s.keepBlocked(m));
      await tester.pump();
      expect(s.pendingList.map((e) => e.id), ['p-blk']);
      expect(s.queued, isNot(contains('p-blk')));
      expect(s.outboxBlockedIds, contains('p-blk'));
      final saved = OfflineOutbox.instance.forChat('private', 'chat_1').single;
      expect(saved.blocked, isTrue);
      expect(saved.pointsKind, 'none', reason: 'tak pernah memotong poin');
    });

    testWidgets('flush MELEWATI entri blokir (tidak dikirim ulang)',
        (tester) async {
      final points = TestPoints();
      final s = await pumpOutbox(tester, points: points);
      await tester.runAsync(() async {
        await OfflineOutbox.instance.enqueue(
          entry('p-old').copyWith(blocked: true),
        );
        await s.flushOutbox();
      });
      expect(s.sentOrder, isEmpty);
      expect(points.deductCalls, 0);
      expect(OfflineOutbox.instance.forChat('private', 'chat_1'), hasLength(1));
    });

    testWidgets('flush ditolak BLOKIR → ditandai, bubble tetap, poin refund',
        (tester) async {
      final points = TestPoints();
      final s = await pumpOutbox(tester, points: points);
      s.sendError = blockedErr;
      s.pendingList.add(pendingMsg('p-q'));
      s.queued.add('p-q');
      await tester.runAsync(() async {
        await OfflineOutbox.instance.enqueue(entry('p-q'));
        await s.flushOutbox();
      });
      await tester.pump();
      expect(points.refundCalls, 1);
      expect(s.pendingList.map((e) => e.id), ['p-q'],
          reason: 'bubble TIDAK dibuang (blokir senyap)');
      expect(s.queued, isNot(contains('p-q')));
      expect(s.outboxBlockedIds, contains('p-q'));
      expect(OfflineOutbox.instance.forChat('private', 'chat_1').single.blocked,
          isTrue);
    });

    testWidgets('buka ulang chat → bubble blokir muncul lagi (centang-1)',
        (tester) async {
      final s = await pumpOutbox(tester);
      await tester.runAsync(() async {
        await OfflineOutbox.instance.enqueue(
          entry('p-back').copyWith(blocked: true),
        );
        await s.loadQueuedForChat();
      });
      await tester.pump();
      expect(s.pendingList.map((e) => e.id), ['p-back']);
      expect(s.queued, isNot(contains('p-back')),
          reason: 'bukan "menunggu koneksi" — memang tak akan terkirim');
      expect(s.outboxBlockedIds, contains('p-back'));
      expect(s.sentOrder, isEmpty);
    });
  });
}
