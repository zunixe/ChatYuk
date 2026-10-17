import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/room_model.dart';
import 'room_provider.dart';

/// Satu baris notifikasi room/grup di tab Chat.
class RoomNotifItem {
  final String id;
  final String name;
  final String icon;
  final bool isGroup;
  final int unread;
  final String lastSenderName;
  final String lastText;
  final String lastType;
  final DateTime? lastAt;

  const RoomNotifItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.isGroup,
    required this.unread,
    required this.lastSenderName,
    required this.lastText,
    required this.lastType,
    required this.lastAt,
  });

  /// Cuplikan baris: "pengirim: teks" (label per jenis media bila kosong).
  String get preview {
    final body = lastText.trim().isNotEmpty
        ? lastText.trim()
        : switch (lastType) {
            'image' => '📷 Foto',
            'video' => '🎬 Video',
            'voice' => '🎤 Pesan suara',
            'sticker' => 'Stiker',
            'location' => '📍 Lokasi',
            _ => '',
          };
    if (lastSenderName.isEmpty) return body;
    return '$lastSenderName: $body';
  }
}

RoomNotifItem _from(RoomModel r, {required bool isGroup}) => RoomNotifItem(
  id: r.id,
  name: r.name,
  icon: r.icon,
  isGroup: isGroup,
  unread: r.unread,
  lastSenderName: r.lastSenderName,
  lastText: r.lastText,
  lastType: r.lastType,
  lastAt: r.lastAt,
);

/// Notifikasi room/grup: gabungan GRUP (`myGroups`) + GLOBAL ROOM
/// (`myGlobalRooms`), hanya yang `unread > 0`, urut pesan terbaru.
///
/// Murni turunan state [roomProvider] — TIDAK ada I/O di sini. Pemuatan
/// data dilakukan `loadMyGroups` / `loadMyGlobalRooms`.
/// Bangun daftar notifikasi dari grup + global room (MURNI — mudah diuji).
List<RoomNotifItem> buildRoomNotifications({
  required List<RoomModel> groups,
  required List<RoomModel> globalRooms,
}) {
  final items = <RoomNotifItem>[
    for (final g in groups)
      if (g.unread > 0) _from(g, isGroup: true),
    for (final r in globalRooms)
      if (r.unread > 0) _from(r, isGroup: false),
  ];
  items.sort((a, b) {
    final at = a.lastAt, bt = b.lastAt;
    if (at == null && bt == null) return 0;
    if (at == null) return 1;
    if (bt == null) return -1;
    return bt.compareTo(at);
  });
  return items;
}

final roomNotificationsProvider = Provider<List<RoomNotifItem>>((ref) {
  final rp = ref.watch(roomProvider);
  return buildRoomNotifications(
    groups: rp.myGroups,
    globalRooms: rp.myGlobalRooms,
  );
});

/// Total unread untuk badge ikon header. `select` sempit: hanya ANGKA,
/// jadi header tidak ikut rebuild saat presence/last-seen berubah.
final roomNotifCountProvider = Provider<int>((ref) {
  var total = 0;
  for (final i in ref.watch(roomNotificationsProvider)) {
    total += i.unread;
  }
  return total;
});
