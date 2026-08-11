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
  String _country = 'Indonesia';
  bool _seeded = false;
  StreamSubscription? _countsSub;
  String? _error;

  List<RoomModel> get rooms => _rooms;
  String get country => _country;
  String? get error => _error;

  RoomProvider() {
    _countsSub = _chat.getRoomOnlineCounts().listen((counts) {
      _counts = counts;
      _applyCounts();
      notifyListeners();
    }, onError: (e) {
      debugPrint('[RoomProvider] counts stream error: $e');
    });
    reload();
  }

  /// Ganti negara & muat room-nya.
  Future<void> setCountry(String country) async {
    if (country == _country) return;
    _country = country;
    notifyListeners();
    await reload();
  }

  Future<void> reload() async {
    try {
      final rooms = await _service.fetchRooms(_country);
      if (_roomsEqual(rooms, _rooms) && _counts.isEmpty) return;
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

  bool _roomsEqual(List<RoomModel> a, List<RoomModel> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].onlineCount != b[i].onlineCount) return false;
    }
    return true;
  }

  void _applyCounts() {
    bool changed = false;
    final updated = _rooms.map((r) {
      final count = _counts[r.id] ?? 0;
      if (r.onlineCount != count) {
        changed = true;
        return r.copyWith(onlineCount: count);
      }
      return r;
    }).toList();
    if (changed) _rooms = updated;
  }

  Future<void> seedRooms() async {
    try {
      await _service.seedCountryRooms(_country);
    } catch (_) {}
  }

  @override
  void dispose() {
    _countsSub?.cancel();
    super.dispose();
  }
}
