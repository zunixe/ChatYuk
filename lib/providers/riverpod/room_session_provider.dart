import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/room_session_model.dart';
import '../../services/room_session_service.dart';

/// State sesi per room: `byRoom[roomId]` = sesi live/terdekat.
class RoomSessionsState {
  final Map<String, RoomSessionInfo> byRoom;
  final bool loading;

  const RoomSessionsState({this.byRoom = const {}, this.loading = false});

  RoomSessionInfo? of(String roomId) => byRoom[roomId];

  @override
  bool operator ==(Object other) =>
      other is RoomSessionsState &&
      other.loading == loading &&
      mapEquals(other.byRoom, byRoom);

  @override
  int get hashCode => Object.hash(loading, Object.hashAllUnordered(byRoom.entries));
}

class RoomSessionNotifier extends Notifier<RoomSessionsState> {
  RoomSessionService get _svc => ref.read(roomSessionServiceProvider);

  List<String> _lastIds = const [];
  DateTime? _lastFetch;
  Timer? _cooldown;

  /// Load sesi untuk daftar room (dipanggil explore/lobby).
  /// Cooldown 20 dtk bila daftar room sama — hemat RPC saat rebuild.
  Future<void> loadFor(List<String> roomIds) async {
    if (roomIds.isEmpty) return;
    final same = listEquals(roomIds, _lastIds);
    final fresh = _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(seconds: 20);
    if (same && fresh) return;
    _lastIds = List.of(roomIds);
    _lastFetch = DateTime.now();
    if (!state.loading) {
      state = RoomSessionsState(byRoom: state.byRoom, loading: true);
    }
    try {
      final list = await _svc.nextSessions(roomIds);
      final map = <String, RoomSessionInfo>{
        for (final s in list) s.roomId: s,
      };
      state = RoomSessionsState(byRoom: map);
    } catch (e) {
      debugPrint('[ROOM-SESSION] load gagal: $e');
      state = RoomSessionsState(byRoom: state.byRoom);
    }
  }

  /// Refresh satu room saja (setelah start/end/tick).
  Future<void> refreshRoom(String roomId) async {
    try {
      final list = await _svc.nextSessions([roomId]);
      final map = Map<String, RoomSessionInfo>.of(state.byRoom);
      if (list.isEmpty) {
        map.remove(roomId);
      } else {
        map[roomId] = list.first;
      }
      state = RoomSessionsState(byRoom: map);
    } catch (e) {
      debugPrint('[ROOM-SESSION] refresh gagal: $e');
    }
  }

  /// Toggle "Ingatkan" — optimistik, rollback bila RPC gagal.
  Future<void> toggleReminder(String roomId) async {
    final cur = state.byRoom[roomId];
    if (cur == null) return;
    final next = Map<String, RoomSessionInfo>.of(state.byRoom);
    next[roomId] = cur.copyWith(reminded: !cur.reminded);
    state = RoomSessionsState(byRoom: next);
    try {
      final reminded = await _svc.toggleReminder(cur.sessionId);
      final after = Map<String, RoomSessionInfo>.of(state.byRoom);
      final s = after[roomId];
      if (s != null) after[roomId] = s.copyWith(reminded: reminded);
      state = RoomSessionsState(byRoom: after);
    } catch (e) {
      debugPrint('[ROOM-SESSION] toggle reminder gagal: $e');
      final back = Map<String, RoomSessionInfo>.of(state.byRoom);
      final s = back[roomId];
      if (s != null) back[roomId] = s.copyWith(reminded: cur.reminded);
      state = RoomSessionsState(byRoom: back);
      rethrow;
    }
  }

  Future<void> startSession(String roomId) async {
    final cur = state.byRoom[roomId];
    if (cur == null) return;
    await _svc.start(cur.sessionId);
    await refreshRoom(roomId);
  }

  Future<void> endSession(String roomId) async {
    final cur = state.byRoom[roomId];
    if (cur == null) return;
    await _svc.end(cur.sessionId);
    await refreshRoom(roomId);
  }

  /// Update peak viewers berkala saat di dalam room live (tanpa dummy).
  Future<void> tick(String roomId) async {
    final cur = state.byRoom[roomId];
    if (cur == null || !cur.isLive) return;
    try {
      final res = await _svc.tick(roomId);
      final peak = (res['peak'] as num?)?.toInt();
      if (peak != null && peak != cur.peakViewers) {
        final map = Map<String, RoomSessionInfo>.of(state.byRoom);
        map[roomId] = cur.copyWith(peakViewers: peak);
        state = RoomSessionsState(byRoom: map);
      }
    } catch (_) {}
  }

  @override
  RoomSessionsState build() {
    ref.onDispose(() => _cooldown?.cancel());
    return const RoomSessionsState();
  }
}

final roomSessionServiceProvider =
    Provider<RoomSessionService>((ref) => RoomSessionService());

final roomSessionProvider =
    NotifierProvider<RoomSessionNotifier, RoomSessionsState>(
        RoomSessionNotifier.new);
