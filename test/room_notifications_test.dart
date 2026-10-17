import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/models/room_model.dart';
import 'package:chatyuk/providers/riverpod/room_notifications_provider.dart';

RoomModel _room({
  required String id,
  String name = 'R',
  int unread = 0,
  String lastSender = '',
  String lastText = '',
  String lastType = 'text',
  DateTime? lastAt,
}) => RoomModel(
  id: id,
  name: name,
  description: '',
  icon: '',
  country: 'Indonesia',
  category: 'general',
  order: 0,
  unread: unread,
  lastSenderName: lastSender,
  lastText: lastText,
  lastType: lastType,
  lastAt: lastAt,
);

void main() {
  group('RoomNotifItem.preview', () {
    test('pengirim + teks digabung', () {
      const item = RoomNotifItem(
        id: '1', name: 'X', icon: '', isGroup: true, unread: 2,
        lastSenderName: 'Budi', lastText: 'halo', lastType: 'text', lastAt: null,
      );
      expect(item.preview, 'Budi: halo');
    });

    test('teks kosong + media -> label jenis', () {
      const img = RoomNotifItem(
        id: '1', name: 'X', icon: '', isGroup: false, unread: 1,
        lastSenderName: 'Ani', lastText: '', lastType: 'image', lastAt: null,
      );
      expect(img.preview, contains('Foto'));
      expect(img.preview, startsWith('Ani: '));
    });

    test('tanpa pengirim -> hanya isi', () {
      const item = RoomNotifItem(
        id: '1', name: 'X', icon: '', isGroup: true, unread: 1,
        lastSenderName: '', lastText: 'tes', lastType: 'text', lastAt: null,
      );
      expect(item.preview, 'tes');
    });
  });

  group('buildRoomNotifications', () {
    test('filter unread=0 dan gabungkan grup + global room', () {
      final now = DateTime.now();
      final items = buildRoomNotifications(
        groups: [
          _room(id: 'g1', name: 'Grup A', unread: 3, lastAt: now),
          _room(id: 'g2', name: 'Grup B', unread: 0, lastAt: now),
        ],
        globalRooms: [
          _room(
            id: 'r1',
            name: 'Room X',
            unread: 1,
            lastAt: now.subtract(const Duration(minutes: 5)),
          ),
          _room(id: 'r2', name: 'Room Y', unread: 0),
        ],
      );
      expect(items.map((e) => e.id), ['g1', 'r1']);
      expect(items.first.isGroup, isTrue);
      expect(items.last.isGroup, isFalse);
    });

    test('urut pesan terbaru (lastAt desc); null paling akhir', () {
      final now = DateTime.now();
      final items = buildRoomNotifications(
        groups: [
          _room(
            id: 'old',
            unread: 1,
            lastAt: now.subtract(const Duration(hours: 2)),
          ),
          _room(id: 'new', unread: 1, lastAt: now),
          _room(id: 'none', unread: 1),
        ],
        globalRooms: const [],
      );
      expect(items.map((e) => e.id), ['new', 'old', 'none']);
    });

    test('total badge = jumlah unread (sum via item)', () {
      final items = buildRoomNotifications(
        groups: [_room(id: 'g', unread: 4)],
        globalRooms: [_room(id: 'r', unread: 2)],
      );
      expect(items.fold<int>(0, (a, e) => a + e.unread), 6);
    });

    test('tanpa unread -> kosong', () {
      final items = buildRoomNotifications(
        groups: [_room(id: 'g', unread: 0)],
        globalRooms: const [],
      );
      expect(items, isEmpty);
    });
  });
}
