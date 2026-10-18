import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import 'package:chatyuk/models/chat_poll.dart';
import 'package:chatyuk/providers/riverpod/poll_provider.dart';
import 'package:chatyuk/services/poll_service.dart';

/// Verifikasi poll GRUP/GLOBAL ROOM memakai RPC/tabel ROOM — dan poll private
/// tetap memakai RPC private (controller terpisah, id pesan antar tabel bisa
/// bertabrakan).
class FakeRoomPollService implements PollService {
  int resultsCalls = 0;
  int resultsRoomCalls = 0;
  int voteCalls = 0;
  int voteRoomCalls = 0;
  List<String> lastIds = [];

  @override
  Future<Map<String, PollResult>> results(List<String> ids) async {
    resultsCalls++;
    return const {};
  }

  @override
  Future<Map<String, PollResult>> resultsRoom(List<String> ids) async {
    resultsRoomCalls++;
    lastIds = ids;
    return {
      for (final id in ids)
        id: PollResult(counts: const [1, 0, 0], mine: const {0}, voters: 1),
    };
  }

  @override
  Future<PollResult?> vote(String id, List<int> options) async {
    voteCalls++;
    return null;
  }

  @override
  Future<PollResult?> voteRoom(String id, List<int> options) async {
    voteRoomCalls++;
    return PollResult(
      counts: const [0, 1, 0],
      mine: options.toSet(),
      voters: 1,
    );
  }

  @override
  RealtimeChannel subscribe(String chatId, void Function(String) onChange) =>
      throw UnimplementedError();

  @override
  RealtimeChannel subscribeRoom(
    String roomId,
    void Function(String) onChange,
  ) => throw UnimplementedError();

  @override
  Future<void> unsubscribe(RealtimeChannel ch) async {}
}

const poll = ChatPoll(
  question: 'Makan apa?',
  options: ['Bakso', 'Soto', 'Mie'],
);

void main() {
  test('controller ROOM memakai RPC room (bukan private)', () async {
    final f = FakeRoomPollService();
    final c = PollController.room(f);
    c.request('7');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(f.resultsRoomCalls, 1);
    expect(f.resultsCalls, 0);
    expect(f.lastIds, ['7']);
    expect(c.listen('7').value!.mine, const {0});

    final ok = await c.vote('7', poll, const {1});
    expect(ok, isTrue);
    expect(f.voteRoomCalls, 1);
    expect(f.voteCalls, 0);
    expect(c.listen('7').value!.mine, const {1});
  });

  test('controller PRIVATE tetap memakai RPC private', () async {
    final f = FakeRoomPollService();
    final c = PollController(f);
    c.request('7');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(f.resultsCalls, 1);
    expect(f.resultsRoomCalls, 0);
    await c.vote('7', poll, const {0});
    expect(f.voteCalls, 1);
    expect(f.voteRoomCalls, 0);
  });
}
