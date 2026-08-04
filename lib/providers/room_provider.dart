import 'dart:async';
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
  StreamSubscription? _roomsSub;
  StreamSubscription? _countsSub;

  List<RoomModel> get rooms => _rooms;

  RoomProvider() {
    _roomsSub = _service.getRooms().listen((rooms) {
      _rooms = rooms;
      _applyCounts();
      if (!_seeded && rooms.isEmpty) {
        _seeded = true;
        seedRooms();
      }
      notifyListeners();
    }, onError: (_) {});

    _countsSub = _chat.getRoomOnlineCounts().listen((counts) {
      bool changed = false;
      for (final r in _rooms) {
        final newCount = counts[r.id] ?? 0;
        if (r.onlineCount != newCount) { changed = true; break; }
      }
      if (changed) {
        _counts = counts;
        _applyCounts();
        notifyListeners();
      }
    }, onError: (_) {});
  }

  void _applyCounts() {
    _rooms = _rooms
        .map((r) => r.onlineCount == (_counts[r.id] ?? 0)
            ? r
            : r.copyWith(onlineCount: _counts[r.id] ?? 0))
        .toList();
  }

  Future<void> seedRooms() async {
    try {
      await _service.seedDefaultRooms();
    } catch (_) {}
  }

  @override
  void dispose() {
    _roomsSub?.cancel();
    _countsSub?.cancel();
    super.dispose();
  }
}
