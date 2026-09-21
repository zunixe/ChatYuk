import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:chatyuk/core/cache/message_cache.dart';
import 'package:chatyuk/core/cache/message_store.dart';
import 'package:chatyuk/core/cache/offline_outbox.dart';
import 'package:chatyuk/mixins/chat_outbox_mixin.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/providers/auth_provider.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/points_provider.dart';
import 'package:chatyuk/services/points_service.dart';

class MockPointsService extends Mock implements PointsService {}

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
}) async {
  final svc = MockPointsService();
  when(() => svc.deductChatPoint(any())).thenAnswer((_) async => deductResult);
  when(() => svc.refundChatPoint(any())).thenAnswer((_) async => 55);
  when(() => svc.watchOwnPoints()).thenAnswer((_) => const Stream.empty());
  when(() => svc.getWallet()).thenAnswer(
    (_) async => <String, dynamic>{'bonus': 0, 'earned': 0, 'total': 50},
  );

  final auth = AuthProvider(autoInit: false);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
        ChangeNotifierProvider<AuthProvider>.value(value: auth),
        // PointsProvider dibuat DI DALAM pumpWidget (di zona FakeAsync) supaya
        // timed-nya milik test ini; Provider akan dispose otomatis.
        ChangeNotifierProvider<PointsProvider>(
          create: (_) => PointsProvider(service: svc),
        ),
      ],
      child: MaterialApp(
        home: OutboxHost(online: online, sendThrows: sendThrows),
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
}
