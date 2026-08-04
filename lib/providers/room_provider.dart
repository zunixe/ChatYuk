import 'package:flutter/foundation.dart';
import '../models/room_model.dart';
import '../services/room_service.dart';
import '../services/chat_service.dart';

class RoomProvider extends ChangeNotifier {
  final RoomService _service = RoomService();
  final ChatService _chat = ChatService();
  List<RoomModel> _rooms = [];
  Map<String, int> _counts = {};
  bool _seeded = false;

  List<RoomModel> get rooms => _rooms;

  RoomProvider() {
    _service.getRooms().listen((rooms) {
      _rooms = rooms;
      _applyCounts();
      if (!_seeded && rooms.isEmpty) {
        _seeded = true;
        seedRooms();
      }
      notifyListeners();
    }, onError: (_) {
      // belum login / auth hilang: abaikan, akan tersambung lagi setelah login
    });

    _chat.getRoomOnlineCounts().listen((counts) {
      _counts = counts;
      _applyCounts();
      notifyListeners();
    }, onError: (_) {});
  }

  void _applyCounts() {
    _rooms = _rooms
        .map((r) => r.copyWith(onlineCount: _counts[r.id] ?? 0))
        .toList();
  }

  Future<void> seedRooms() async {
    try {
      await _service.seedDefaultRooms();
    } catch (_) {
      // rooms dikelola server (admin SDK); client tidak boleh menulis.
      // Seed di sisi client akan ditolak rules — abaikan.
    }
  }
}
