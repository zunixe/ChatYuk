import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/room_session_model.dart';

/// RPC Room v2 (sesi terjadwal + host) — 20261111120000_room_sessions_v2.sql.
/// Screen TIDAK boleh import file ini langsung — pakai roomSessionProvider.
class RoomSessionService {
  final SupabaseClient? _injected;
  RoomSessionService([SupabaseClient? sb]) : _injected = sb;

  SupabaseClient get _sb => _injected ?? SupabaseConfig.client;

  /// Sesi live/terdekat per room (1 baris per room, join host + reminded).
  Future<List<RoomSessionInfo>> nextSessions(List<String> roomIds) async {
    if (roomIds.isEmpty) return const [];
    final res = await _sb.rpc(
      'next_room_sessions',
      params: {'p_room_ids': roomIds},
    );
    final rows = (res as List?) ?? const [];
    return rows
        .whereType<Map>()
        .map((r) => RoomSessionInfo.fromJson(Map<String, dynamic>.from(r)))
        .toList(growable: false);
  }

  /// Toggle "Ingatkan" → true bila sekarang terdaftar.
  Future<bool> toggleReminder(int sessionId) async {
    final res = await _sb.rpc(
      'toggle_session_reminder',
      params: {'p_session_id': sessionId},
    );
    return (res is Map && res['reminded'] == true);
  }

  Future<void> start(int sessionId) async {
    await _sb.rpc('start_room_session', params: {'p_session_id': sessionId});
  }

  Future<void> end(int sessionId) async {
    await _sb.rpc('end_room_session', params: {'p_session_id': sessionId});
  }

  /// Update peak_viewers sesi live (tanpa dummy) — dipanggil berkala dari room.
  Future<Map<String, dynamic>> tick(String roomId) async {
    final res = await _sb.rpc('room_session_tick', params: {'p_room_id': roomId});
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Admin: jadwalkan sesi.
  Future<int> schedule({
    required String roomId,
    required String hostUid,
    required String title,
    required String format,
    required DateTime startsAt,
    required DateTime endsAt,
  }) async {
    final res = await _sb.rpc('schedule_room_session', params: {
      'p_room_id': roomId,
      'p_host_uid': hostUid,
      'p_title': title,
      'p_format': format,
      'p_starts_at': startsAt.toUtc().toIso8601String(),
      'p_ends_at': endsAt.toUtc().toIso8601String(),
    });
    return ((res as Map)['session_id'] as num).toInt();
  }

  /// Admin: set flag host.
  Future<void> adminSetHost(String uid, bool isHost) async {
    await _sb.rpc('admin_set_host',
        params: {'p_uid': uid, 'p_is_host': isHost});
  }

  /// Admin: KPI sesi.
  Future<Map<String, dynamic>> adminStats({int days = 30}) async {
    final res =
        await _sb.rpc('admin_room_session_stats', params: {'p_days': days});
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Admin: daftar sesi (tabel stats) — read-only via RLS select publik.
  Future<List<Map<String, dynamic>>> adminListSessions({int limit = 100}) async {
    final rows = await _sb
        .from('room_sessions')
        .select(
            'id,room_id,title,format,starts_at,ends_at,status,started_at,ended_at,peak_viewers,gifts_total,host_uid')
        .order('starts_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList(growable: false);
  }

  /// Admin: user yang is_host (untuk pilihan host di form jadwal).
  Future<List<Map<String, dynamic>>> listHosts() async {
    final rows = await _sb
        .from('profiles')
        .select('id,nickname,avatar')
        .eq('is_host', true)
        .limit(200);
    return (rows as List)
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList(growable: false);
  }
}
