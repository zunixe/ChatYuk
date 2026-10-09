import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/cache/message_cache.dart';
import '../../models/room_model.dart';
import '../../services/chat_service.dart';
import '../../services/private_room_service.dart';
import '../../services/realtime_hub.dart';
import '../../services/room_broadcast_service.dart';
import '../../services/room_service.dart';
export '../../services/room_broadcast_service.dart' show RoomBroadcastSession;
import '../../services/rt_resilient.dart';
import '../../utils.dart';

/// State room (immutable — yang di-watch widget).
class RoomState {
  final List<RoomModel> rooms;
  final List<RoomModel> privateRooms;
  final Set<String> memberRoomIds;
  final String country;
  final String? error;
  final bool hasLoaded;
  final List<RoomModel> myGroups;
  final bool myGroupsLoading;
  final String exploreCategory;
  final List<RoomModel> explore;
  final bool exploreLoading;

  const RoomState({
    this.rooms = const [],
    this.privateRooms = const [],
    this.memberRoomIds = const {},
    this.country = 'Indonesia',
    this.error,
    this.hasLoaded = false,
    this.myGroups = const [],
    this.myGroupsLoading = false,
    this.exploreCategory = 'rame',
    this.explore = const [],
    this.exploreLoading = false,
  });

  @override
  bool operator ==(Object other) =>
      other is RoomState &&
      other.country == country &&
      other.error == error &&
      other.hasLoaded == hasLoaded &&
      other.myGroupsLoading == myGroupsLoading &&
      other.exploreCategory == exploreCategory &&
      other.exploreLoading == exploreLoading &&
      listEquals(other.rooms, rooms) &&
      listEquals(other.privateRooms, privateRooms) &&
      listEquals(other.myGroups, myGroups) &&
      listEquals(other.explore, explore) &&
      setEquals(other.memberRoomIds, memberRoomIds);

  @override
  int get hashCode => Object.hash(
        country,
        error,
        hasLoaded,
        myGroupsLoading,
        exploreCategory,
        exploreLoading,
        Object.hashAll(rooms),
        Object.hashAll(privateRooms),
        Object.hashAll(myGroups),
        Object.hashAll(explore),
        Object.hashAllUnordered(memberRoomIds),
      );

  List<RoomModel> get exploreRooms {
    final list = exploreCategory == 'rame'
        ? explore.where((r) => r.onlineCount > 0).toList()
        : explore.where((r) => r.category == exploreCategory).toList();
    list.sort((a, b) {
      final on = b.onlineCount.compareTo(a.onlineCount);
      if (on != 0) return on;
      final atA = a.lastAt;
      final atB = b.lastAt;
      if (atA == null || atB == null) return atA == null ? 1 : -1;
      return atB.compareTo(atA);
    });
    return list;
  }

  String get exploreSig {
    final parts = <String>[];
    for (final r in explore) {
      parts.add(
        '${r.id}\u0001${r.onlineCount}\u0001${r.category}\u0001'
        '${r.lastAt?.millisecondsSinceEpoch ?? 0}\u0001${r.name}',
      );
    }
    parts.sort();
    return '$exploreCategory\u0002${parts.join('\u0003')}';
  }
}

/// Daftar room/grup + explore (Riverpod). Migrasi dari ChangeNotifier.
/// Global (persist sepanjang sesi).
class RoomNotifier extends Notifier<RoomState> {
  final RoomService _service;
  final ChatService _chat;

  RoomNotifier(
      {RoomService? service, ChatService? chatService, bool autoInit = true})
      : _service = service ?? RoomService(),
        _chat = chatService ?? ChatService(),
        _autoInit = autoInit;

  final bool _autoInit;
  var _disposed = false;

  List<RoomModel> _rooms = [];
  List<RoomModel> _privateRooms = [];
  Set<String> _memberRoomIds = {};
  Map<String, int> _counts = {};
  /// Room yang sudah dibuka user (badge unread dipaksa 0). Bertahan lintas
  /// `fetchExplore` supaya badge TIDAK muncul lagi akibat race: RPC
  /// `mark_room_read` bisa belum selesai saat fetchExplore menimpa `_explore`
  /// dengan data server yang masih unread>0.
  final Set<String> _readRoomIds = {};
  String _country = 'Indonesia';
  bool _seeded = false;
  StreamSubscription? _countsSub;
  StreamSubscription? _privateSub;
  StreamSubscription? _membershipSub;
  StreamSubscription? _presenceSub;
  String? _error;
  Timer? _diskSaveTimer;
  final Completer<void> _warm = Completer<void>();
  bool _warmDone = false;
  bool _hasLoaded = false;

  List<RoomModel> _myGroups = [];
  DateTime? _myGroupsAt;
  String? _myGroupsUid;
  bool _myGroupsLoading = false;
  static const _myGroupsTtl = Duration(seconds: 30);

  String _exploreCategory = 'rame';
  List<RoomModel> _explore = [];
  DateTime? _exploreAt;
  String? _exploreCountry;
  bool _exploreLoading = false;
  static const _exploreTtl = Duration(seconds: 30);

  @override
  RoomState build() {
    ref.onDispose(_disposeAll);
    if (!_autoInit) return const RoomState();
    _presenceSub = RealtimeHub.instance.roomPresence.listen((msg) {
      final roomId = msg['roomId'] as String?;
      final state = msg['state'] as Map?;
      if (roomId == null || state == null) return;
      var total = 0;
      for (final v in state.values) {
        if (v is List) total += v.length;
      }
      final current = _counts[roomId] ?? 0;
      if (total <= current) return;
      _counts = {..._counts, roomId: total};
      _applyCounts();
      _emit();
    }, onError: (e) => dlog('[RoomProvider] presence stream error: $e'));
    _subscribeCounts();
    _subscribePrivateRooms();
    _subscribeMembership();
    _loadDisk();
    reload();
    return const RoomState();
  }

  void _emit() {
    if (_disposed) return;
    state = RoomState(
      rooms: List.unmodifiable(_rooms),
      privateRooms: List.unmodifiable(_privateRooms),
      memberRoomIds: Set.unmodifiable(_memberRoomIds),
      country: _country,
      error: _error,
      hasLoaded: _hasLoaded,
      myGroups: List.unmodifiable(_myGroups),
      myGroupsLoading: _myGroupsLoading,
      exploreCategory: _exploreCategory,
      explore: List.unmodifiable(_explore),
      exploreLoading: _exploreLoading,
    );
  }

  // ── Getter kompat ──
  List<RoomModel> get rooms => _rooms;
  List<RoomModel> get privateRooms => _privateRooms;
  Set<String> get memberRoomIds => _memberRoomIds;
  String get country => _country;
  String? get error => _error;
  bool get hasLoaded => _hasLoaded;
  List<RoomModel> get myGroups => _myGroups;
  bool get myGroupsLoading => _myGroupsLoading;
  String get exploreCategory => _exploreCategory;
  List<RoomModel> get exploreRooms => state.exploreRooms;
  bool get exploreLoading => _exploreLoading;
  String get exploreSig => state.exploreSig;
  Future<void> get warmFuture => _warm.future;

  void _markWarm() {
    if (_warmDone) return;
    _warmDone = true;
    if (!_warm.isCompleted) _warm.complete();
  }

  void setExploreCategory(String id) {
    if (_exploreCategory == id) return;
    _exploreCategory = id;
    _emit();
  }

  Future<void> fetchExplore({bool refresh = false}) async {
    if (_exploreLoading) return;
    final fresh = !refresh &&
        _exploreAt != null &&
        _exploreCountry == _country &&
        DateTime.now().difference(_exploreAt!) < _exploreTtl;
    if (fresh && _explore.isNotEmpty) return;
    _exploreLoading = true;
    _emit();
    try {
      final rows = await _service.fetchExplore(_country);
      _explore = rows
          .map((e) => RoomModel.fromMap('${e['id'] ?? ''}', snakeToCamel(e)))
          .toList();
      // Paksa unread=0 untuk room yang sudah dibuka user — jaga badge tetap
      // hilang walau RPC mark_room_read belum sempat tersimpan di server.
      if (_readRoomIds.isNotEmpty) {
        _explore = _explore
            .map((r) => _readRoomIds.contains(r.id) && r.unread != 0
                ? r.copyWith(unread: 0)
                : r)
            .toList();
      }
      _explore = _explore.map((r) {
        final c = _counts[r.id];
        return c != null ? r.copyWith(onlineCount: c) : r;
      }).toList();
      _exploreAt = DateTime.now();
      _exploreCountry = _country;
      _emit();
      _scheduleDiskSave();
    } catch (e) {
      dlog('[RoomProvider] fetchExplore error: $e');
    } finally {
      _exploreLoading = false;
      _emit();
    }
  }

  Future<Map<String, dynamic>> createGlobalRoom({
    required String name,
    required String icon,
    required String category,
  }) async {
    final res = await _service.createGlobalRoom(
      name: name,
      icon: icon,
      country: _country,
      category: category,
    );
    await fetchExplore(refresh: true);
    return res;
  }

  Future<void> markRoomRead(String roomId) async {
    _readRoomIds.add(roomId);
    _explore = _explore
        .map((r) => r.id == roomId ? r.copyWith(unread: 0) : r)
        .toList();
    _emit();
    await _service.markRoomRead(roomId);
  }

  // ── Passthrough (Fase 9b) ──
  final PrivateRoomService _prv = PrivateRoomService.instance;
  String? get prvUid => _prv.uid;
  Future<String?> myRole(String roomId) => _prv.myRole(roomId);
  Future<List<Map<String, dynamic>>> listMembers(String roomId) =>
      _prv.listMembers(roomId);
  Future<List<Map<String, dynamic>>> listMyRooms() => _prv.listMyRooms();
  Future<List<Map<String, dynamic>>> listJoinRequests(String roomId) =>
      _prv.listJoinRequests(roomId);
  Future<void> invite(String roomId, String uid) => _prv.invite(roomId, uid);
  Future<void> approveJoin(String roomId, String uid) =>
      _prv.approveJoin(roomId, uid);
  Future<void> rejectJoin(String roomId, String uid) =>
      _prv.rejectJoin(roomId, uid);
  Future<void> kick(String roomId, String uid) => _prv.kick(roomId, uid);
  Future<void> setRole(String roomId, String uid, String role) =>
      _prv.setRole(roomId, uid, role);
  Future<Map<String, dynamic>> updateRoomIcon(String roomId, String icon) =>
      _prv.updateRoomIcon(roomId, icon);
  Future<void> leavePrivate(String roomId) => _prv.leave(roomId);
  Future<void> rotateToken(String roomId) => _prv.rotateToken(roomId);
  Future<void> grantBroadcast(String roomId, String uid) =>
      _prv.grantBroadcast(roomId, uid);
  Future<void> revokeBroadcast(String roomId, String uid) =>
      _prv.revokeBroadcast(roomId, uid);
  Future<bool> myBroadcastGranted(String roomId) =>
      _prv.myBroadcastGranted(roomId);
  Future<int> broadcastCount(String roomId) => _prv.broadcastCount(roomId);
  Future<void> startBroadcast(String roomId) => _prv.startBroadcast(roomId);
  Future<void> stopBroadcast(String roomId) => _prv.stopBroadcast(roomId);
  Future<void> sendSignal(
    String roomId, {
    required String type,
    String? toUid,
    Map<String, dynamic> payload = const {},
  }) =>
      _prv.sendSignal(roomId, type: type, toUid: toUid, payload: payload);

  Future<Set<String>> fetchMyMemberships(String uid) =>
      _service.fetchMyMemberships(uid);
  Future<List<Map<String, dynamic>>> fetchRoomsByIds(List<String> ids) =>
      _service.fetchRoomsByIds(ids);
  Future<Map<String, dynamic>?> fetchRoomById(String id) =>
      _service.fetchRoomById(id);
  Future<Map<String, dynamic>> resetRoomPassword(String id, String? pass) =>
      _service.resetRoomPassword(id, pass);

  Future<void> loadMyGroups({bool refresh = false}) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    if (_myGroupsLoading) return;
    final fresh = !refresh &&
        _myGroupsAt != null &&
        _myGroupsUid == uid &&
        DateTime.now().difference(_myGroupsAt!) < _myGroupsTtl;
    if (fresh) return;
    _myGroupsLoading = true;
    _emit();
    if (_myGroups.isEmpty) await _loadMyGroupsDisk(uid);
    try {
      final rows = await PrivateRoomService.instance.listMyRooms();
      final groups = rows
          .map((r) => RoomModel.fromMap('${r['id'] ?? ''}', r))
          .toList();
      _myGroups = groups;
      _myGroupsAt = DateTime.now();
      _myGroupsUid = uid;
      _scheduleMyGroupsSave();
    } catch (e) {
      dlog('[RoomProvider] load my groups error: $e');
    } finally {
      _myGroupsLoading = false;
      _emit();
    }
  }

  Future<void> _loadMyGroupsDisk(String uid) async {
    try {
      final obj = await MessageCache.instance.loadRawObj('my_groups_$uid');
      final raw = obj['groups'];
      if (raw is! List || raw.isEmpty) return;
      if (_myGroups.isNotEmpty) return;
      _myGroups = raw
          .map((e) => RoomModel.fromMap(
              '${(e as Map)['id'] ?? ''}', Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      dlog('[RoomProvider] my groups disk load error: $e');
    }
  }

  void _scheduleMyGroupsSave() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    MessageCache.instance.saveRawObj(
      'my_groups_$uid',
      {'groups': _myGroups.map((r) => r.toMap()).toList()},
    );
  }

  RoomBroadcastSession createBroadcastSession({
    required String roomId,
    required bool isBroadcaster,
    VoidCallback? onEnded,
  }) =>
      RoomBroadcastSession(
        roomId: roomId,
        isBroadcaster: isBroadcaster,
        onEnded: onEnded,
      );

  void _subscribeCounts() {
    _countsSub?.cancel();
    _countsSub = listenResilient<Map<String, int>>(
      () => _chat.getRoomOnlineCounts(country: _country),
      (counts) {
        if (_countsEquals(counts, _counts)) return;
        _counts = counts;
        _applyCounts();
        _emit();
      },
      isDisposed: () => _disposed,
      onError: (e) {
        dlog('[RoomProvider] counts stream error: $e');
      },
    );
  }

  Future<void> _loadDisk() async {
    try {
      final obj = await MessageCache.instance.loadRawObj('rooms_$_country');
      if (obj.isEmpty) return;
      final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
      final memObj = uid.isEmpty
          ? <String, dynamic>{}
          : await MessageCache.instance.loadRawObj('members_$uid');
      if (_rooms.isNotEmpty) return;
      _rooms = ((obj['rooms'] as List?) ?? const [])
          .map((e) => RoomModel.fromMap(
              '${(e as Map)['id'] ?? ''}', Map<String, dynamic>.from(e)))
          .toList();
      _privateRooms = ((obj['private'] as List?) ?? const [])
          .map((e) => RoomModel.fromMap(
              '${(e as Map)['id'] ?? ''}', Map<String, dynamic>.from(e)))
          .toList();
      _explore = ((obj['explore'] as List?) ?? const [])
          .map((e) => RoomModel.fromMap(
              '${(e as Map)['id'] ?? ''}', Map<String, dynamic>.from(e)))
          .toList();
      if (_explore.isNotEmpty) {
        _exploreAt = DateTime.now();
        _exploreCountry = _country;
      }
      _memberRoomIds = ((memObj['ids'] as List?) ?? const [])
          .map((e) => '$e')
          .toSet();
      _hasLoaded = true;
      _emit();
    } catch (e) {
      dlog('[RoomProvider] disk load error: $e');
      _hasLoaded = true;
    } finally {
      _markWarm();
    }
  }

  void _scheduleDiskSave() {
    _diskSaveTimer?.cancel();
    _diskSaveTimer = Timer(const Duration(seconds: 2), () {
      if (_rooms.isEmpty && _privateRooms.isEmpty) return;
      MessageCache.instance.saveRawObj('rooms_$_country', {
        'rooms': _rooms.map((r) => r.toMap()).toList(),
        'private': _privateRooms.map((r) => r.toMap()).toList(),
        'explore': _explore.map((r) => r.toMap()).toList(),
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

  void _subscribePrivateRooms() {
    _privateSub?.cancel();
    _membershipSub?.cancel();
    _privateSub = listenResilient<List<RoomModel>>(
      () => _service.watchPrivateRooms(_country),
      (rooms) {
        _privateRooms = rooms;
        _applyCounts();
        _hasLoaded = true;
        _emit();
        _scheduleDiskSave();
      },
      isDisposed: () => _disposed,
      onError: (e) {
        dlog('[RoomProvider] private rooms stream error: $e');
      },
    );
  }

  void _subscribeMembership() {
    _membershipSub?.cancel();
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    _membershipSub = listenResilient<List<Map<String, dynamic>>>(
      () => Supabase.instance.client
          .from('room_members')
          .stream(primaryKey: ['room_id', 'user_id'])
          .eq('user_id', uid),
      (_) {
        loadMyGroups(refresh: true);
      },
      isDisposed: () => _disposed,
      onError: (e) => dlog('[RoomProvider] membership stream error: $e'),
    );
  }

  Future<void> setCountry(String country) async {
    if (country == _country) return;
    _country = country;
    _subscribeCounts();
    _subscribePrivateRooms();
    _emit();
    if (_rooms.isEmpty && _privateRooms.isEmpty) _loadDisk();
    await reload();
  }

  Future<void> reload() async {
    try {
      final rooms = await _service.fetchRooms(_country);
      if (_roomsEqual(rooms, _rooms) && _counts.isEmpty) {
        await reloadPrivate();
        return;
      }
      _rooms = rooms;
      _applyCounts();
      _hasLoaded = true;
      _markWarm();
      if (!_seeded && rooms.isEmpty) {
        _seeded = true;
        seedRooms();
      }
      _error = null;
      _emit();
      _scheduleDiskSave();
      await reloadPrivate();
    } catch (e) {
      dlog('[RoomProvider] fetch rooms error: $e');
      _error = e.toString();
      _hasLoaded = true;
      _markWarm();
      _emit();
    }
  }

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
      _hasLoaded = true;
      _markWarm();
      _emit();
      _scheduleDiskSave();
    } catch (e) {
      dlog('[RoomProvider] fetch private rooms error: $e');
      _hasLoaded = true;
      _markWarm();
    }
  }

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
    await loadMyGroups(refresh: true);
    return res;
  }

  Future<Map<String, dynamic>> joinPrivateRoom(
    String roomId, {
    String? password,
  }) async {
    final res = await _service.joinPrivateRoom(roomId, password: password);
    if (res['ok'] == true) {
      _memberRoomIds = {..._memberRoomIds, roomId};
      _emit();
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
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].onlineCount != b[i].onlineCount) {
        return false;
      }
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
    var changed = false;
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

    _explore = _explore.map((r) {
      final count = _counts[r.id];
      return count != null && r.onlineCount != count
          ? r.copyWith(onlineCount: count)
          : r;
    }).toList();
  }

  Future<void> seedRooms() async {
    try {
      await _service.seedCountryRooms(_country);
    } catch (_) {}
  }

  void _disposeAll() {
    _disposed = true;
    _diskSaveTimer?.cancel();
    _countsSub?.cancel();
    _privateSub?.cancel();
    _membershipSub?.cancel();
    _presenceSub?.cancel();
    _markWarm();
  }
}

final roomProvider =
    NotifierProvider<RoomNotifier, RoomState>(RoomNotifier.new);
