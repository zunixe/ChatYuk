import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/room_model.dart';

class RoomService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<RoomModel>> getRooms() {
    return _db.collection('rooms').orderBy('order').snapshots().map((snap) {
      return snap.docs.map((doc) {
        final data = doc.data();
        return RoomModel.fromMap(doc.id, data);
      }).toList();
    });
  }

  Future<void> seedDefaultRooms() async {
    final rooms = [
      {'id': 'general', 'name': 'General', 'description': 'Obrolan umum untuk semua', 'icon': '💬', 'order': 1},
      {'id': 'curhat', 'name': 'Curhat', 'description': 'Cerita dan curhat bareng', 'icon': '🤗', 'order': 2},
      {'id': 'pertemanan', 'name': 'Pertemanan', 'description': 'Cari temen baru di sini', 'icon': '🤝', 'order': 3},
      {'id': 'teknologi', 'name': 'Teknologi', 'description': 'Diskusi tech & gadget', 'icon': '💻', 'order': 4},
      {'id': 'gaming', 'name': 'Gaming', 'description': 'Main bareng & diskusi game', 'icon': '🎮', 'order': 5},
      {'id': 'musik', 'name': 'Musik', 'description': 'Sharing musik & lagu', 'icon': '🎵', 'order': 6},
      {'id': 'film', 'name': 'Film & TV', 'description': 'Rekomendasi & review film', 'icon': '🎬', 'order': 7},
      {'id': 'joke', 'name': 'Joke & Meme', 'description': 'Yang bikin ngakak', 'icon': '😂', 'order': 8},
      {'id': 'belajar', 'name': 'Belajar', 'description': 'Diskusi belajar & kuliah', 'icon': '📚', 'order': 9},
      {'id': 'flirt', 'name': 'Flirt', 'description': 'Ngobrol santai & asyik', 'icon': '😉', 'order': 10},
    ];

    final batch = _db.batch();
    for (final room in rooms) {
      final ref = _db.collection('rooms').doc(room['id'] as String);
      batch.set(ref, {
        'name': room['name'],
        'description': room['description'],
        'icon': room['icon'],
        'order': room['order'],
        'onlineCount': 0,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> updateOnlineCount(String roomId, int count) async {
    await _db.collection('rooms').doc(roomId).update({'onlineCount': count});
  }
}
