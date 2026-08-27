import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/room_model.dart';
import '../services/room_service.dart';
import '../services/chat_service.dart';
import '../services/message_cache.dart';
import '../services/realtime_hub.dart';

class RoomProvider extends ChangeNotifier {
  final RoomService _service = RoomService();
  final ChatService _chat = ChatService();
  List<RoomModel> _rooms = [];
  List<RoomModel> _privateRooms = [];
  Set<String> _memberRoomIds = {};
  Map<String, int> _counts = {};
  String _country = 'Indonesia';
  bool _seeded = false;
  StreamSubscription? _countsSub;
  StreamSubscription? _privateSub;
  String? _error;
  Timer? _diskSaveTimer;

  List<RoomModel> get rooms => _rooms;
  List<RoomModel> get privateRooms => _privateRooms;
  Set<String> get memberRoomIds => _memberRoomIds;
  String get country => _country;
  String? get error => _error;

  RoomProvider() {
    // Unified fan-out: Presence room juga update counts per-room
    RealtimeHub.instance.roomPresence.listen((msg) {
      final roomId = msg['roomId'] as String?;
      final state = msg['state'] as Map?;
      if (roomId == null || state == null) return;
      int total = 0;
      for (final v in state.values) {
        if (v is List) total += v.length;
      }
      if (_counts[roomId] == total) return;
      _counts = {..._counts, roomId: total};
      _applyCounts();
      notifyListeners();
    });
    _countsSub = _chat.getRoomOnlineCounts().listen(
      (counts) {
        // Event presence (heartbeat 60s tiap user) tidak mengubah count —
        // lewati notify supaya lobby tidak rebuild tiap detik.
        if (_countsEquals(counts, _counts)) return;
        _counts = counts;
        _applyCounts();
        notifyListeners();
      },
      onError: (e) {
        debugPrint('[RoomProvider] counts stream error: $e');
      },
    );
    _subscribePrivateRooms();
    _loadDisk();
    reload();
  }

  // ── Persist list room ke disk (encrypted) — cold start tampil instan ────
  Future<void> _loadDisk() async {
    try {
      final obj = await MessageCache.instance.loadRawObj('rooms_$_country');
      if (obj.isEmpty) return;
      final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
      final memObj = uid.isEmpty
          ? <String, dynamic>{}
          : await MessageCache.instance.loadRawObj('members_$uid');
      if (_rooms.isNotEmpty) return; // server sudah lebih dulu
      _rooms = ((obj['rooms'] as List?) ?? const [])
          .map((e) => RoomModel.fromMap(
              '${(e as Map)['id'] ?? ''}', Map<String, dynamic>.from(e)))
          .toList();
      _privateRooms = ((obj['private'] as List?) ?? const [])
          .map((e) => RoomModel.fromMap(
              '${(e as Map)['id'] ?? ''}', Map<String, dynamic>.from(e)))
          .toList();
      _memberRoomIds = ((memObj['ids'] as List?) ?? const [])
          .map((e) => '$e')
          .toSet();
      notifyListeners();
    } catch (e) {
      debugPrint('[RoomProvider] disk load error: $e');
    }
  }

  void _scheduleDiskSave() {
    _diskSaveTimer?.cancel();
    _diskSaveTimer = Timer(const Duration(seconds: 2), () {
      if (_rooms.isEmpty && _privateRooms.isEmpty) return;
      MessageCache.instance.saveRawObj('rooms_$_country', {
        'rooms': _rooms.map((r) => r.toMap()).toList(),
        'private': _privateRooms.map((r) => r.toMap()).toList(),
      });
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        MessageCache.instance.saveRawObj(
          'members_$uid',
          {'ids': _memberRoomIds.toList()},
        );
      }
    });
  }

  /// Berlangganan realtime perubahan private room untuk negara aktif.
  /// Saat ada room dibuat/dihapus di device manapun, list langsung sinkron.
  void _subscribePrivateRooms() {
    _privateSub?.cancel();
    _privateSub = _service
        .watchPrivateRooms(_country)
        .listen(
          (rooms) {
            _privateRooms = rooms;
            _applyCounts();
            notifyListeners();
            _scheduleDiskSave();
          },
          onError: (e) {
            debugPrint('[RoomProvider] private rooms stream error: $e');
          },
        );
  }

  /// Ganti negara & muat room-nya.
  Future<void> setCountry(String country) async {
    if (country == _country) return;
    _country = country;
    _subscribePrivateRooms(); // langganan ulang untuk negara baru
    notifyListeners();
    // Tampilkan cache disk negara itu dulu kalau memori kosong.
    if (_rooms.isEmpty && _privateRooms.isEmpty) _loadDisk();
    await reload();
  }

  Future<void> reload() async {
    try {
      final rooms = await _service.fetchRooms(_country);
      if (_roomsEqual(rooms, _rooms) && _counts.isEmpty) {
        // tetap refresh private room walau global tidak berubah
        await reloadPrivate();
        return;
      }
      _rooms = rooms;
      _applyCounts();
      if (!_seeded && rooms.isEmpty) {
        _seeded = true;
        seedRooms();
      }
      _error = null;
      notifyListeners();
      _scheduleDiskSave();
      await reloadPrivate();
    } catch (e) {
      debugPrint('[RoomProvider] fetch rooms error: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Muat ulang private room + membership untuk negara aktif.
  Future<void> reloadPrivate() async {
    try {
      await _service.cleanupExpired();
      final priv = await _service.fetchPrivateRooms(_country);
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final members = uid != null
          ? await _service.fetchMyMemberships(uid)
          : <String>{};
      _privateRooms = priv;
      _memberRoomIds = members;
      _applyCounts();
      notifyListeners();
      _scheduleDiskSave();
    } catch (e) {
      debugPrint('[RoomProvider] fetch private rooms error: $e');
    }
  }

  /// Buat private room; refresh list & kembalikan id baru.
  Future<Map<String, dynamic>> createPrivateRoom({
    required String name,
    required String icon,
    String? password,
  }) async {
    final res = await _service.createPrivateRoom(
      name: name,
      icon: icon,
      country: _country,
      password: password,
    );
    await reloadPrivate();
    return res;
  }

  Future<Map<String, dynamic>> joinPrivateRoom(
    String roomId, {
    String? password,
  }) async {
    final res = await _service.joinPrivateRoom(roomId, password: password);
    if (res['ok'] == true) {
      _memberRoomIds = {..._memberRoomIds, roomId};
      notifyListeners();
    }
    return res;
  }

  Future<Map<String, dynamic>> extendRoom(String roomId) async {
    final res = await _service.extendRoom(roomId);
    await reloadPrivate();
    return res;
  }

  Future<void> deleteRoom(String roomId) async {
    await _service.deleteRoom(roomId);
    await reloadPrivate();
  }

  bool _roomsEqual(List<RoomModel> a, List<RoomModel> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].onlineCount != b[i].onlineCount)
        return false;
    }
    return true;
  }

  bool _countsEquals(Map<String, int> a, Map<String, int> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
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

    _privateRooms = _privateRooms.map((r) {
      final count = _counts[r.id] ?? 0;
      return r.onlineCount != count ? r.copyWith(onlineCount: count) : r;
    }).toList();
  }

  Future<void> seedRooms() async {
    try {
      await _service.seedCountryRooms(_country);
    } catch (_) {}
  }

  @override
  void dispose() {
    _diskSaveTimer?.cancel();
    _countsSub?.cancel();
    _privateSub?.cancel();
    super.dispose();
  }
}
