import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/chat_poll.dart';
import '../utils.dart';

/// I/O poll private chat: hasil (batch), vote, realtime suara per chat.
class PollService {
  PollService._();
  static final PollService instance = PollService._();

  SupabaseClient get _sb => Supabase.instance.client;

  /// Hasil banyak poll sekaligus (lazy load bubble yang terlihat).
  Future<Map<String, PollResult>> results(List<String> messageIds) async {
    final ids = messageIds
        .map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);
    if (ids.isEmpty) return const {};
    try {
      final res = await _sb.rpc('get_poll_results', params: {
        'p_message_ids': ids,
      });
      final out = <String, PollResult>{};
      if (res is List) {
        for (final r in res) {
          final pr = PollResult.tryParse(r);
          if (pr != null && r is Map) out['${r['id']}'] = pr;
        }
      }
      return out;
    } catch (e) {
      dlog('[Poll] results error: $e');
      return const {};
    }
  }

  /// Ganti pilihan saya (kosong = tarik suara). null bila gagal.
  Future<PollResult?> vote(String messageId, List<int> options) async {
    final id = int.tryParse(messageId);
    if (id == null) return null;
    try {
      final res = await _sb.rpc('vote_poll', params: {
        'p_message_id': id,
        'p_options': options,
      });
      return PollResult.tryParse(res);
    } catch (e) {
      dlog('[Poll] vote error: $e');
      return null;
    }
  }

  /// Realtime perubahan suara di satu chat → [onChange] (id pesan poll).
  RealtimeChannel subscribe(String chatId, void Function(String) onChange) {
    final ch = _sb.channel('poll_votes_$chatId');
    ch
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_poll_votes',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: chatId,
          ),
          callback: (p) {
            final rec = p.newRecord.isNotEmpty ? p.newRecord : p.oldRecord;
            final mid = '${rec['message_id'] ?? ''}';
            if (mid.isNotEmpty) onChange(mid);
          },
        )
        .subscribe();
    return ch;
  }

  Future<void> unsubscribe(RealtimeChannel ch) async {
    try {
      await _sb.removeChannel(ch);
    } catch (_) {}
  }
}
