part of '../admin_provider.dart';

/// Monitor GRUP (private rooms user) — daftar grup, anggota, pesan per-room.
///
/// Pola sama dengan [AdminChatsMx]:
///  - cache disk (offline-first) via [MessageCache],
///  - dedupe in-flight (satu fetch per filter/room sekaligus),
///  - pesan per-room di map (LRU) — TIDAK ada buffer bersama (cegah pesan
///    room lain kecampur, pola insiden admin chat buffer global),
///  - pagination + poll 5 dtk (realtime ditangani di layar view).
mixin AdminRoomsMx on AdminBase {
  // ── Daftar grup ──
  List<Map<String, dynamic>> _rooms = [];
  bool _roomsLoading = false;
  bool _roomsHasMore = true;
  bool _roomsFetchingMore = false;
  int _roomsTotal = 0;
  AdminErrKind? _roomsError;
  String _roomsSearch = '';
  String _roomsCountry = '';
  Future<void>? _roomsInFlight;

  List<Map<String, dynamic>> get rooms => _rooms;
  bool get roomsLoading => _roomsLoading;
  bool get roomsHasMore => _roomsHasMore;
  AdminErrKind? get roomsError => _roomsError;
  String get roomsSearch => _roomsSearch;
  String get roomsCountry => _roomsCountry;

  static const int roomsPageSize = 50;

  /// Simpan filter aktif (dipakai layar untuk highlight chip).
  void setRoomsFilter({String? search, String? country}) {
    if (search != null) _roomsSearch = search;
    if (country != null) _roomsCountry = country;
  }

  Future<void> fetchRooms() async {
    if (_roomsLoading) return;
    _roomsLoading = true;
    _roomsError = null;
    _notifyRooms();
    final filterSig = '$_roomsSearch|$_roomsCountry';
    // Cold start / belum ada data → cache disk dulu (tahan offline).
    if (_rooms.isEmpty) {
      try {
        final cached = await MessageCache.instance.loadRawList(
          '${AdminBase.kAdminRoomsKey}_$filterSig',
        );
        if (cached.isNotEmpty && _rooms.isEmpty) {
          _rooms = cached;
          _roomsTotal = cached.length;
          _notifyRooms();
        }
      } catch (_) {}
    }
    try {
      final res = await _service.listPrivateRoomsPage(
        limit: roomsPageSize,
        offset: 0,
        search: _roomsSearch,
        country: _roomsCountry,
      );
      final fresh = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      _rooms = fresh;
      _roomsTotal = (res['total'] as num?)?.toInt() ?? 0;
      _roomsHasMore = _rooms.length < _roomsTotal;
      if (_rooms.isNotEmpty) {
        MessageCache.instance.saveRawList(
          '${AdminBase.kAdminRoomsKey}_$filterSig',
          _rooms,
        );
      }
    } catch (e) {
      _roomsError = classifyAdminError(e);
      dlog('[ADMIN] fetchRooms error: $e');
    }
    _roomsLoading = false;
    _notifyRooms();
  }

  /// Fetch dengan dedupe (panggilan bersamaan menunggu future yang sama).
  Future<void> fetchRoomsDeduped() {
    final existing = _roomsInFlight;
    if (existing != null) return existing;
    final f = fetchRooms().whenComplete(() => _roomsInFlight = null);
    _roomsInFlight = f;
    return f;
  }

  Future<void> fetchMoreRooms() async {
    if (_roomsFetchingMore || !_roomsHasMore || _roomsLoading) return;
    _roomsFetchingMore = true;
    try {
      final res = await _service.listPrivateRoomsPage(
        limit: roomsPageSize,
        offset: _rooms.length,
        search: _roomsSearch,
        country: _roomsCountry,
      );
      final more = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      final ids = _rooms.map((r) => '${r['id']}').toSet();
      for (final r in more) {
        if (ids.add('${r['id']}')) _rooms.add(r);
      }
      _roomsHasMore = _rooms.length < _roomsTotal;
      _notifyRooms();
    } catch (e) {
      dlog('[ADMIN] fetchMoreRooms error: $e');
    }
    _roomsFetchingMore = false;
  }

  // ── Anggota satu grup ──
  final Map<String, List<Map<String, dynamic>>> _roomMembersCache = {};
  List<Map<String, dynamic>> roomMembersFor(String roomId) =>
      _roomMembersCache[roomId] ?? const [];

  Future<List<Map<String, dynamic>>> fetchRoomMembers(
    String roomId, {
    bool force = false,
  }) async {
    if (!force && _roomMembersCache.containsKey(roomId)) {
      return _roomMembersCache[roomId]!;
    }
    try {
      final list = await _service.getRoomMembers(roomId);
      _roomMembersCache[roomId] = list;
      return list;
    } catch (e) {
      dlog('[ADMIN] fetchRoomMembers $roomId error: $e');
      return _roomMembersCache[roomId] ?? const [];
    }
  }

  // ── Pesan per-room (map LRU — TIDAK buffer bersama) ──
  static const int _roomMsgMemMax = 12;
  final Map<String, List<Map<String, dynamic>>> _roomMsgMem = {};
  final Map<String, bool> _roomMsgHasMore = {};
  Future<void>? _roomMsgInFlight;
  final Map<String, Future<void>?> _roomMsgFetchMoreInFlight = {};

  /// Pesan satu grup dari memori (sumber tunggal per-room).
  List<Map<String, dynamic>> roomMessagesFor(String roomId) =>
      _roomMsgMem[roomId] ?? const [];
  bool roomMessagesHasMoreFor(String roomId) => _roomMsgHasMore[roomId] ?? true;

  void _touchRoomMsg(String roomId, List<Map<String, dynamic>> rows) {
    _roomMsgMem.remove(roomId);
    _roomMsgMem[roomId] = rows;
    while (_roomMsgMem.length > _roomMsgMemMax) {
      final first = _roomMsgMem.keys.first;
      _roomMsgMem.remove(first);
      _roomMsgHasMore.remove(first);
    }
  }

  /// Muat pesan grup (lokal disk dulu, baru server). Skip server bila sudah
  /// ada di memori & tidak dipaksa (buka-ulang instan).
  Future<void> fetchRoomMessages(
    String roomId, {
    bool force = false,
    int limit = 50,
  }) async {
    if (!force && _roomMsgMem.containsKey(roomId)) return;
    final existing = _roomMsgInFlight;
    if (existing != null) return existing;
    final f = _doFetchRoomMessages(roomId, limit: limit)
        .whenComplete(() => _roomMsgInFlight = null);
    _roomMsgInFlight = f;
    return f;
  }

  Future<void> _doFetchRoomMessages(
    String roomId, {
    required int limit,
  }) async {
    // Disk dulu (instan, tahan offline).
    if (!_roomMsgMem.containsKey(roomId)) {
      try {
        final cached = await MessageCache.instance
            .loadRawList(AdminBase.adminRoomMsgKey(roomId));
        if (cached.isNotEmpty && !_roomMsgMem.containsKey(roomId)) {
          _touchRoomMsg(roomId, cached);
          _roomMsgHasMore[roomId] = true;
          _notifyRooms();
        }
      } catch (_) {}
    }
    try {
      final res = await _service.getRoomMessagesPage(roomId, limit: limit, offset: 0);
      final items = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      final total = (res['total'] as num?)?.toInt() ?? items.length;
      _touchRoomMsg(roomId, items);
      _roomMsgHasMore[roomId] = items.length < total;
      if (items.isNotEmpty) {
        MessageCache.instance
            .saveRawList(AdminBase.adminRoomMsgKey(roomId), items);
      }
    } catch (e) {
      dlog('[ADMIN] fetchRoomMessages $roomId error: $e');
    }
    _notifyRooms();
  }

  /// Muat halaman lebih lama (scroll ke atas). Merge by id (union, DESC).
  Future<void> fetchMoreRoomMessages(String roomId, {int limit = 50}) async {
    if (_roomMsgFetchMoreInFlight[roomId] != null) return;
    if (!(_roomMsgHasMore[roomId] ?? true)) return;
    final current = _roomMsgMem[roomId] ?? const [];
    final f = () async {
      try {
        final res = await _service.getRoomMessagesPage(
          roomId,
          limit: limit,
          offset: current.length,
        );
        final more = List<Map<String, dynamic>>.from(res['items'] ?? const []);
        final total = (res['total'] as num?)?.toInt() ?? 0;
        final merged = mergeAdminChatMessages(current, more).merged;
        _touchRoomMsg(roomId, merged);
        _roomMsgHasMore[roomId] = merged.length < total;
        _notifyRooms();
      } catch (e) {
        dlog('[ADMIN] fetchMoreRoomMessages $roomId error: $e');
      }
    }()
        .whenComplete(() => _roomMsgFetchMoreInFlight[roomId] = null);
    _roomMsgFetchMoreInFlight[roomId] = f;
    return f;
  }

  /// Poll ringan: tarik halaman-1 & merge (dipakai timer 5 dtk layar view).
  Future<void> refreshRoomMessages(String roomId, {int limit = 30}) async {
    try {
      final current = _roomMsgMem[roomId] ?? const [];
      final res = await _service.getRoomMessagesPage(roomId, limit: limit, offset: 0);
      final latest = List<Map<String, dynamic>>.from(res['items'] ?? const []);
      if (current.isEmpty) {
        if (latest.isNotEmpty) {
          _touchRoomMsg(roomId, latest);
          _notifyRooms();
        }
        return;
      }
      final merged = mergeAdminChatMessages(current, latest);
      if (merged.changed) {
        _touchRoomMsg(roomId, merged.merged);
        _notifyRooms();
      }
    } catch (e) {
      dlog('[ADMIN] refreshRoomMessages $roomId error: $e');
    }
  }

  /// Ambil image_data satu pesan (lazy foto grup).
  Future<String> fetchRoomMessageImage(int messageId) =>
      _service.fetchRoomMessageImage(messageId);
}
