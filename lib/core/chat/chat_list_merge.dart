import '../../models/room_model.dart';
import 'private_chat_info.dart';
import '../cache/group_pin_store.dart';

DateTime _epoch0() => DateTime.fromMillisecondsSinceEpoch(0);

/// Susun daftar Pesan: **semua item TERSEMAT di paling atas** — chat private
/// DAN grup — diurutkan waktu disematkan (terbaru dulu). Baru setelah itu:
/// chat private (urutan aktivitas yang sudah dihitung pemanggil) lalu grup
/// (urut aktivitas terbaru).
///
/// Dulu pemanggil memakai `[...chats, ...groups]` sehingga grup tersemat
/// tertahan di bawah seluruh chat private — laporan user: "sematkan grup
/// tidak naik ke paling atas".
///
/// Fungsi MURNI (tanpa widget/DB) → mudah diuji.
List<Object> mergePinnedFirstChats({
  required List<PrivateChatInfo> chats,
  required List<RoomModel> groups,
  required String myUid,
  bool groupsOnly = false,
}) {
  final pinned = <({DateTime at, Object item})>[];
  final restChats = <PrivateChatInfo>[];
  final restGroups = <RoomModel>[];

  for (final c in chats) {
    final at = c.pinnedAtFor(myUid);
    if (c.isPinnedFor(myUid)) {
      pinned.add((at: at ?? _epoch0(), item: c));
    } else {
      restChats.add(c);
    }
  }
  for (final g in groups) {
    if (GroupPinStore.isPinned(g.id)) {
      pinned.add((
        at: GroupPinStore.pinnedAt(g.id) ?? _epoch0(),
        item: g,
      ));
    } else {
      restGroups.add(g);
    }
  }

  pinned.sort((a, b) => b.at.compareTo(a.at));
  restGroups.sort(
    (a, b) => (b.lastAt ?? _epoch0()).compareTo(a.lastAt ?? _epoch0()),
  );

  final top = <Object>[
    for (final p in pinned)
      if (!groupsOnly || p.item is RoomModel) p.item,
  ];
  if (groupsOnly) return [...top, ...restGroups];
  return [...top, ...restChats, ...restGroups];
}
