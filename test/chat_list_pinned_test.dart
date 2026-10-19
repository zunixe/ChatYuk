import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/core/cache/group_pin_store.dart';
import 'package:chatyuk/core/chat/chat_list_merge.dart';
import 'package:chatyuk/models/room_model.dart';
import 'package:chatyuk/services/chat_service.dart' show PrivateChatInfo;

const me = 'me';

PrivateChatInfo chat(
  String id, {
  DateTime? at,
  DateTime? pinnedAt,
}) => PrivateChatInfo(
  chatId: id,
  participants: const ['me', 'other'],
  participantNames: const {'other': 'Orang'},
  lastMessage: 'hi',
  lastMessageAt: at ?? DateTime(2026, 10, 18, 12),
  pinnedBy: pinnedAt == null ? const [] : const [me],
  pinnedAt: pinnedAt == null ? const {} : {me: pinnedAt},
);

RoomModel grp(String id, {DateTime? at}) => RoomModel(
  id: id,
  name: 'Grup $id',
  description: '',
  icon: '',
  country: '',
  category: '',
  order: 0,
  lastAt: at,
);

void main() {
  setUp(GroupPinStore.resetForTest);
  tearDown(GroupPinStore.resetForTest);

  test('GRUP tersemat naik ke PALING ATAS (di atas chat private terbaru)', () {
    final chats = [
      chat('c1', at: DateTime(2026, 10, 18, 13)), // paling baru
      chat('c2', at: DateTime(2026, 10, 18, 12)),
    ];
    GroupPinStore.toggle('g1');
    final groups = [grp('g1', at: DateTime(2026, 10, 18, 9)), grp('g2')];

    final out = mergePinnedFirstChats(
      chats: chats,
      groups: groups,
      myUid: me,
    );
    expect(out.first, isA<RoomModel>());
    expect((out.first as RoomModel).id, 'g1'); // ← bug yang dilaporkan
    expect(out.map((e) => e is RoomModel ? 'g:${e.id}' : (e as PrivateChatInfo).chatId),
        ['g:g1', 'c1', 'c2', 'g:g2']);
  });

  test('tersemat campuran diurutkan waktu disematkan (terbaru dulu)', () async {
    final chats = [chat('c1', pinnedAt: DateTime(2026, 10, 18, 10))];
    GroupPinStore.toggle('g1');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    GroupPinStore.toggle('g2'); // lebih baru disematkan
    final out = mergePinnedFirstChats(
      chats: chats,
      groups: [grp('g1'), grp('g2'), grp('g3')],
      myUid: me,
    );
    expect(
      out.take(3).map(
        (e) => e is RoomModel ? 'g:${e.id}' : (e as PrivateChatInfo).chatId,
      ),
      ['g:g2', 'g:g1', 'c1'],
    );
    expect((out.last as RoomModel).id, 'g3');
  });

  test('filter GRUP: hanya grup, tersemat di atas & sisanya urut aktivitas', () {
    GroupPinStore.toggle('g2');
    final out = mergePinnedFirstChats(
      chats: [chat('c1')],
      groups: [
        grp('g1', at: DateTime(2026, 10, 18, 11)),
        grp('g2', at: DateTime(2026, 10, 18, 9)),
        grp('g3', at: DateTime(2026, 10, 18, 12)),
      ],
      myUid: me,
      groupsOnly: true,
    );
    expect(out.map((e) => (e as RoomModel).id), ['g2', 'g3', 'g1']);
  });

  test('tanpa sematan: chat dulu (urutan pemanggil) lalu grup urut aktivitas', () {
    final out = mergePinnedFirstChats(
      chats: [chat('c1')],
      groups: [grp('g1', at: DateTime(2026, 10, 18, 9)), grp('g2', at: DateTime(2026, 10, 18, 10))],
      myUid: me,
    );
    expect((out.first as PrivateChatInfo).chatId, 'c1');
    expect(out.skip(1).map((e) => (e as RoomModel).id), ['g2', 'g1']);
  });
}
