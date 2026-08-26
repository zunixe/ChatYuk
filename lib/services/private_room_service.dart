import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import 'room_service.dart';

/// Service private room v2: role, approval queue, live broadcast state,
/// signaling WebRTC (mesh) via tabel room_signals.
class PrivateRoomService {
  PrivateRoomService._();
  static final PrivateRoomService instance = PrivateRoomService._();

  SupabaseClient get _sb => SupabaseConfig.client;
  String? get uid => _sb.auth.currentUser?.id;

  // ── Query ──

  /// Role saya di room (null = bukan member).
  Future<String?> myRole(String roomId) async {
    final res = await _sb.rpc(
      'fn_room_role',
      params: {'p_uid': uid, 'p_room_id': roomId},
    );
    return res is String ? res : null;
  }

  /// Daftar member + role (owner dulu, lalu admin, lalu member).
  Future<List<Map<String, dynamic>>> listMembers(String roomId) async {
    final res = await _sb.rpc('list_room_members_v2', params: {'p_room_id': roomId});
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  /// Antrean approval (hanya terlihat oleh owner/admin via guard RPC).
  Future<List<Map<String, dynamic>>> listJoinRequests(String roomId) async {
    final res = await _sb.rpc('list_room_join_requests', params: {'p_room_id': roomId});
    if (res is List) {
      return res.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  // ── Aksi moderasi / keanggotaan ──

  Future<void> requestJoin(String roomId) async {
    // RPC join_private_room lama → antrean approval bila approval_required.
    await RoomService().joinPrivateRoom(roomId);
  }

  Future<void> approveJoin(String roomId, String targetUid) async {
    await _sb.rpc('approve_join_request', params: {
      'p_room_id': roomId,
      'p_uid': targetUid,
    });
  }

  Future<void> rejectJoin(String roomId, String targetUid) async {
    await _sb.rpc('reject_join_request', params: {
      'p_room_id': roomId,
      'p_uid': targetUid,
    });
  }

  Future<void> kick(String roomId, String targetUid) async {
    await _sb.rpc('kick_room_member', params: {
      'p_room_id': roomId,
      'p_uid': targetUid,
    });
  }

  Future<void> setRole(String roomId, String targetUid, String role) async {
    await _sb.rpc('set_member_role', params: {
      'p_room_id': roomId,
      'p_uid': targetUid,
      'p_role': role,
    });
  }

  Future<void> leave(String roomId) async {
    await _sb.rpc('leave_private_room', params: {'p_room_id': roomId});
  }

  Future<void> rotateToken(String roomId) async {
    final token = _randomToken();
    await _sb.from('rooms').update({'join_token': token}).eq('id', roomId);
  }

  String _randomToken() {
    final rand = DateTime.now().microsecondsSinceEpoch;
    return rand.toRadixString(36).padLeft(10, '0') +
        uid.toString().substring(0, 4);
  }

  // ── Broadcast grant/stop ──

  Future<void> grantBroadcast(String roomId, String targetUid) async {
    await _sb.rpc('grant_broadcast', params: {
      'p_room_id': roomId,
      'p_uid': targetUid,
    });
  }

  Future<void> stopBroadcast(String roomId) async {
    await _sb.rpc('stop_broadcast', params: {'p_room_id': roomId});
  }

  // ── Signaling (room_signals) ──

  /// Subscribe semua signal untuk satu room (INSERT saja — ephemeral).
  Stream<Map<String, dynamic>> onSignal(String roomId) {
    final controller = StreamController<Map<String, dynamic>>.broadcast();
    final channel = _sb.channel('room-signal-$roomId-${uid ?? 'anon'}');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'room_signals',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'room_id',
        value: roomId,
      ),
      callback: (payload) {
        if (controller.isClosed) return;
        final row = Map<String, dynamic>.from(payload.newRecord);
        // Abaikan signal sendiri.
        if ('${row['from_uid']}' == uid) return;
        controller.add(row);
      },
    );
    channel.subscribe();
    controller.onCancel = () => _sb.removeChannel(channel);
    return controller.stream;
  }

  /// Kirim signal ke satu member (to) atau broadcast (to = null).
  Future<void> sendSignal(
    String roomId, {
    required String type,
    String? toUid,
    Map<String, dynamic> payload = const {},
  }) async {
    try {
      await _sb.from('room_signals').insert({
        'room_id': roomId,
        'from_uid': uid,
        'to_uid': toUid,
        'type': type,
        'payload': payload,
      });
    } catch (e) {
      debugPrint('[PRIVROOM] sendSignal $type error: $e');
    }
  }

  /// Ambil signal yang terlewat saat offline/refresh (cursor id).
  Future<List<Map<String, dynamic>>> fetchSignalsSince(
    String roomId,
    int sinceId,
  ) async {
    try {
      final rows = await _sb
          .from('room_signals')
          .select()
          .eq('room_id', roomId)
          .gt('id', sinceId)
          .order('id')
          .limit(200);
      return rows
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((r) => '${r['from_uid']}' != uid)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}