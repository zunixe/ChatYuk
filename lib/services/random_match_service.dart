import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/random_match.dart';
import '../utils.dart';

/// I/O fitur Random Video Call: antrean match (RPC), realtime baris antrean
/// sendiri, data radar, dan riwayat. Tidak ada UI di sini.
class RandomMatchService {
  RandomMatchService._();
  static final RandomMatchService instance = RandomMatchService._();

  SupabaseClient get _sb => Supabase.instance.client;
  String? get uid => _sb.auth.currentUser?.id;

  /// Masuk antrean. Return `{status: 'waiting'}` atau
  /// `{status: 'matched', call_id, is_caller, partner:{...}}`.
  Future<Map<String, dynamic>> join(String wantGender) async {
    final res = await _sb.rpc(
      'random_match_join',
      params: {'p_want_gender': wantGender},
    );
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  /// Heartbeat 10 dtk + cek apakah sudah dipasangkan orang lain.
  Future<Map<String, dynamic>> ping() async {
    final res = await _sb.rpc('random_match_ping');
    return res is Map ? Map<String, dynamic>.from(res) : const {};
  }

  Future<void> leave() async {
    await _sb.rpc('random_match_leave');
  }

  /// Jumlah penunggu/online + sampel avatar untuk radar.
  Future<({int waiting, int online, List<RandomRadarUser> sample})>
  stats() async {
    final res = await _sb.rpc('random_match_stats');
    if (res is! Map) {
      return (waiting: 0, online: 0, sample: const <RandomRadarUser>[]);
    }
    final raw = res['sample'];
    final sample = <RandomRadarUser>[
      if (raw is List)
        for (final r in raw)
          if (RandomRadarUser.tryParse(r) case final u?) u,
    ];
    return (
      waiting: (res['waiting'] as num?)?.toInt() ?? 0,
      online: (res['online'] as num?)?.toInt() ?? 0,
      sample: sample,
    );
  }

  Future<List<RandomCallEntry>> history({
    int limit = 30,
    int offset = 0,
  }) async {
    try {
      final res = await _sb.rpc(
        'random_call_history',
        params: {'p_limit': limit, 'p_offset': offset},
      );
      if (res is! List) return const [];
      return [
        for (final r in res)
          if (r is Map)
            if (RandomCallEntry.tryParse(Map<String, dynamic>.from(r))
                case final e?)
              e,
      ];
    } catch (e) {
      dlog('[RandomMatch] history error: $e');
      return const [];
    }
  }

  /// Sinyal realtime: baris antrean SAYA berubah (dipasangkan orang lain).
  /// Emit sekali per perubahan; pemanggil wajib `cancel()` saat selesai.
  Stream<void> watchQueue() {
    final me = uid;
    if (me == null) return const Stream.empty();
    final controller = StreamController<void>.broadcast();
    final channel = _sb.channel('random-match-$me');
    void onChange(PostgresChangePayload _) {
      if (!controller.isClosed) controller.add(null);
    }

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'random_match_queue',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: me,
          ),
          callback: onChange,
        )
        .subscribe((status, err) {
          if (err != null) dlog('[RandomMatch] realtime error: $err');
        });
    controller.onCancel = () => _sb.removeChannel(channel);
    return controller.stream;
  }
}
