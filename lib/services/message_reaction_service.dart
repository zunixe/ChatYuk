import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils.dart';

class MessageReactionService {
  MessageReactionService._();
  static final MessageReactionService instance = MessageReactionService._();
  SupabaseClient get _sb => SupabaseConfig.client;

  Future<bool> toggleReaction({
    required String chatType,
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    final me = _sb.auth.currentUser?.id;
    if (me == null || messageId.startsWith('pending-')) return false;
    try {
      final existing = await _sb
          .from('message_reactions')
          .select('id')
          .eq('chat_type', chatType)
          .eq('message_id', messageId)
          .eq('user_id', me)
          .eq('emoji', emoji)
          .maybeSingle();
      if (existing != null) {
        await _sb
            .from('message_reactions')
            .delete()
            .eq('id', (existing as Map)['id']);
        return false;
      }
      await _sb.from('message_reactions').insert({
        'chat_type': chatType,
        'chat_id': chatId,
        'message_id': messageId,
        'user_id': me,
        'emoji': emoji,
      });
      return true;
    } catch (e) {
      dlog('[Reaction] toggle error: $e');
      return false;
    }
  }

  Stream<Map<String, Map<String, int>>> watchReactions(String chatId) {
    try {
      return _sb
          .from('message_reactions')
          .stream(primaryKey: ['id'])
          .eq('chat_id', chatId)
          .map((rows) {
        final out = <String, Map<String, int>>{};
        for (final r in rows) {
          final mid = '${r['message_id'] ?? ''}';
          final emoji = '${r['emoji'] ?? ''}';
          if (mid.isEmpty || emoji.isEmpty) continue;
          final per = out.putIfAbsent(mid, () => {});
          per[emoji] = (per[emoji] ?? 0) + 1;
        }
        return out;
      });
    } catch (_) {
      return Stream.value({});
    }
  }

  Future<bool> isStarred({
    required String chatType,
    required String messageId,
  }) async {
    final me = _sb.auth.currentUser?.id;
    if (me == null) return false;
    try {
      final row = await _sb
          .from('starred_messages')
          .select('id')
          .eq('user_id', me)
          .eq('chat_type', chatType)
          .eq('message_id', messageId)
          .maybeSingle();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> toggleStar({
    required String chatType,
    required String chatId,
    required String messageId,
  }) async {
    final me = _sb.auth.currentUser?.id;
    if (me == null || messageId.startsWith('pending-')) return false;
    try {
      final existing = await _sb
          .from('starred_messages')
          .select('id')
          .eq('user_id', me)
          .eq('chat_type', chatType)
          .eq('message_id', messageId)
          .maybeSingle();
      if (existing != null) {
        await _sb
            .from('starred_messages')
            .delete()
            .eq('id', (existing as Map)['id']);
        return false;
      }
      await _sb.from('starred_messages').insert({
        'user_id': me,
        'chat_type': chatType,
        'chat_id': chatId,
        'message_id': messageId,
      });
      return true;
    } catch (e) {
      dlog('[Star] toggle error: $e');
      return false;
    }
  }

  Stream<Set<String>> watchStarred(String chatId) {
    final me = _sb.auth.currentUser?.id;
    if (me == null) return Stream.value({});
    try {
      return _sb
          .from('starred_messages')
          .stream(primaryKey: ['id'])
          .eq('user_id', me)
          .eq('chat_id', chatId)
          .map((rows) => {
                for (final r in rows) '${r['message_id'] ?? ''}',
              }..remove(''));
    } catch (_) {
      return Stream.value({});
    }
  }
}
