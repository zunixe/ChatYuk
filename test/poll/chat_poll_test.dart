import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/core/chat/pending_confirm.dart';
import 'package:chatyuk/models/chat_poll.dart';
import 'package:chatyuk/models/message_model.dart';
import 'package:chatyuk/providers/riverpod/poll_provider.dart';
import 'package:chatyuk/services/poll_service.dart';
import 'package:chatyuk/widgets/poll/poll_bubble.dart';
import 'package:chatyuk/widgets/poll/poll_composer_sheet.dart';

class FakePollService implements PollService {
  int resultCalls = 0;
  List<String> lastIds = [];
  bool failVote = false;
  final Map<String, PollResult> server = {};
  Completer<void>? gate;

  @override
  Future<Map<String, PollResult>> results(List<String> ids) async {
    resultCalls++;
    lastIds = ids;
    await gate?.future;
    return {for (final id in ids) if (server[id] != null) id: server[id]!};
  }

  @override
  Future<PollResult?> vote(String id, List<int> options) async {
    if (failVote) return null;
    return PollResult(counts: const [0, 1, 0], mine: options.toSet(), voters: 1);
  }

  @override
  RealtimeChannel subscribe(String chatId, void Function(String) onChange) =>
      throw UnimplementedError();

  @override
  Future<void> unsubscribe(RealtimeChannel ch) async {}
}

const poll = ChatPoll(question: 'Makan apa?', options: ['Bakso', 'Soto', 'Mie']);

MessageModel pollMsg(String id, {DateTime? at}) => MessageModel(
  id: id,
  senderId: 'u1',
  senderName: 'A',
  senderGender: 'male',
  isRegistered: true,
  text: poll.previewText,
  type: 'poll',
  imageData: '',
  timestamp: at ?? DateTime(2026, 10, 18, 12),
  poll: poll,
);

void main() {
  group('ChatPoll model', () {
    test('parse Map & string JSON, tolak tak valid', () {
      expect(ChatPoll.tryParse({'q': 'x', 'o': ['a', 'b'], 'm': true})!.multi, isTrue);
      expect(ChatPoll.tryParse('{"q":"x","o":["a","b"]}')!.options, ['a', 'b']);
      expect(ChatPoll.tryParse({'q': '', 'o': ['a', 'b']}), isNull);
      expect(ChatPoll.tryParse({'q': 'x', 'o': ['a']}), isNull);
      expect(ChatPoll.tryParse('rusak'), isNull);
    });

    test('ikut cache pesan (toMap/fromMap) & hilang saat dihapus', () {
      final m = pollMsg('1');
      final back = MessageModel.fromMap('1', m.toMap());
      expect(back.poll!.question, 'Makan apa?');
      expect(back.poll!.options.length, 3);
      expect(m.copyWith(isDeleted: true).poll, isNull);
    });
  });

  group('PollController', () {
    test('banyak request → SATU RPC (batch lazy)', () async {
      final f = FakePollService();
      final c = PollController(f);
      c.request('1');
      c.request('2');
      c.request('3');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(f.resultCalls, 1);
      expect(f.lastIds.toSet(), {'1', '2', '3'});
    });

    test('id pending tidak di-request', () async {
      final f = FakePollService();
      PollController(f).request('pending-123');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(f.resultCalls, 0);
    });

    test('vote optimistik lalu nilai server; gagal → rollback', () async {
      final f = FakePollService();
      final c = PollController(f);
      final ok = await c.vote('9', poll, {1});
      expect(ok, isTrue);
      expect(c.listen('9').value!.mine, {1});
      f.failVote = true;
      final before = c.listen('9').value;
      final ok2 = await c.vote('9', poll, {2});
      expect(ok2, isFalse);
      expect(identical(c.listen('9').value, before), isTrue);
    });

    test('cache bounded', () {
      final c = PollController(FakePollService());
      for (var i = 0; i < 260; i++) {
        c.listen('m$i');
      }
      expect(c.cachedCount, lessThanOrEqualTo(200));
    });
  });

  test('dedupe pending poll vs gema server', () {
    final used = <String>{};
    final pend = [pollMsg('pending-1')];
    final srv = pollMsg('77', at: DateTime(2026, 10, 18, 13));
    expect(
      consumeConfirmedPoll(
        server: srv,
        openedAt: DateTime(2026, 10, 18, 12, 30),
        consumedIds: used,
        pendings: pend,
      ),
      0,
    );
  });

  testWidgets('PollBubble: lengkap di frame-1 & ukuran TETAP saat hasil datang', (t) async {
    final f = FakePollService()
      ..gate = Completer<void>()
      ..server['5'] = const PollResult(counts: [2, 1, 0], mine: {0}, voters: 3);
    final c = PollController(f);
    await t.pumpWidget(
      ProviderScope(
        overrides: [pollProvider.overrideWithValue(c)],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: PollBubble(msg: pollMsg('5'), chatId: '', timeStr: '4:10 PM'),
            ),
          ),
        ),
      ),
    );
    // Frame-1 (hasil belum datang): pertanyaan + semua opsi sudah ada.
    expect(find.text('Makan apa?'), findsOneWidget);
    for (final o in poll.options) {
      expect(find.text(o), findsOneWidget);
    }
    final before = t.getSize(find.byType(PollBubble));
    f.gate!.complete();
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('2'), findsOneWidget);
    expect(t.getSize(find.byType(PollBubble)), before, reason: 'tanpa lompatan layout');
  });

  testWidgets('PollBubble: tap opsi memanggil vote (optimistik)', (t) async {
    final f = FakePollService();
    final c = PollController(f);
    await t.pumpWidget(
      ProviderScope(
        overrides: [pollProvider.overrideWithValue(c)],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: PollBubble(msg: pollMsg('6'), chatId: '', timeStr: '4:10 PM'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('Soto'));
    await t.pump(const Duration(milliseconds: 300));
    expect(c.listen('6').value!.mine, {1});
  });

  testWidgets('Sheet buat polling: validasi & hasil ChatPoll', (t) async {
    ChatPoll? out;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  out = await PollComposerSheet.show(ctx, s: S(isId: false)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const ValueKey('poll_question')), 'Kapan?');
    await t.enterText(find.byKey(const ValueKey('poll_option_0')), 'Senin');
    await t.enterText(find.byKey(const ValueKey('poll_option_1')), 'Selasa');
    await t.pump();
    // Opsi terakhir terisi → kolom ke-3 muncul otomatis.
    expect(find.byKey(const ValueKey('poll_option_2')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('poll_send')));
    await t.pumpAndSettle();
    expect(out, isNotNull);
    expect(out!.question, 'Kapan?');
    expect(out!.options, ['Senin', 'Selasa']);
  });
}
