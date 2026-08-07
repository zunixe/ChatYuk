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
  StreamSubscription? _roomsSub;
  StreamSubscription? _countsSub;
  Timer? _pollTimer;
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
      await _service.seedCountryRooms(_country);
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
