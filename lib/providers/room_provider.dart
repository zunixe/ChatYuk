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
  Timer? _pollTimer;
  String? _error;

  List<RoomModel> get rooms => _rooms;
  String? get error => _error;

  RoomProvider() {
    _pollTimer = Timer.periodic(const Duration(minutes: 5), (_) => reload());
    reload();

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
    }, onError: (e) {
      debugPrint('[RoomProvider] counts stream error: $e');
    });
  }

  Future<void> reload() async {
    try {
      final rooms = await _service.fetchRooms();
      _rooms = rooms;
      _applyCounts();
      if (!_seeded && rooms.isEmpty) {
        _seeded = true;
        seedRooms();
      }
      _error = null;
      notifyListeners();
    } catch (e) {
      debugPrint('[RoomProvider] fetch rooms error: $e');
      _error = e.toString();
      notifyListeners();
    }
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
    _pollTimer?.cancel();
    _roomsSub?.cancel();
    _countsSub?.cancel();
    super.dispose();
  }
}
