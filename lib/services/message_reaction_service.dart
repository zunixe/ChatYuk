import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../utils.dart';
import '../core/cache/message_cache.dart';

enum ToggleResult { added, removed, failed }

class MessageReactionService {
  /// Client opsional (LAZY) — test menyuntik client palsu tanpa
  /// `Supabase.instance`. Produksi: `SupabaseConfig.client`.
  final SupabaseClient? _injected;
  MessageReactionService._([SupabaseClient? sb]) : _injected = sb;

  static MessageReactionService instance = MessageReactionService._();

  @visibleForTesting
  factory MessageReactionService.forTest(SupabaseClient sb) =>
      MessageReactionService._(sb);

  @visibleForTesting
  static void overrideInstance(MessageReactionService s) => instance = s;

  @visibleForTesting
  static void restoreInstance() => instance = MessageReactionService._();

  SupabaseClient get _sb => _injected ?? SupabaseConfig.client;

  Future<ToggleResult> toggleReaction({
    required String chatType,
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    final me = _sb.auth.currentUser?.id;
    if (me == null || messageId.startsWith('pending-')) {
      return ToggleResult.failed;
    }
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
        return ToggleResult.removed;
      }
      await _sb.from('message_reactions').insert({
        'chat_type': chatType,
        'chat_id': chatId,
        'message_id': messageId,
        'user_id': me,
        'emoji': emoji,
      });
      return ToggleResult.added;
    } catch (e) {
      dlog('[Reaction] toggle error: $e');
      return ToggleResult.failed;
    }
  }

  Future<bool> removeReaction({
    required String chatType,
    required String messageId,
    required String emoji,
  }) async {
    final me = _sb.auth.currentUser?.id;
    if (me == null) return false;
    try {
      await _sb
          .from('message_reactions')
          .delete()
          .eq('chat_type', chatType)
          .eq('message_id', messageId)
          .eq('user_id', me)
          .eq('emoji', emoji);
      return true;
    } catch (e) {
      dlog('[Reaction] remove error: $e');
      return false;
    }
  }

  Future<List<Map<String, String>>> fetchReactors({
    required String chatType,
    required String messageId,
  }) async {
    try {
      final rows = await _sb
          .from('message_reactions')
          .select('user_id,emoji,created_at')
          .eq('chat_type', chatType)
          .eq('message_id', messageId)
          .order('created_at');
      final out = <Map<String, String>>[];
      for (final row in rows as List) {
        final r = row as Map;
        final userId = '${r['user_id'] ?? ''}';
        final emoji = '${r['emoji'] ?? ''}';
        if (userId.isEmpty || emoji.isEmpty) continue;
        out.add({'userId': userId, 'emoji': emoji});
      }
      return out;
    } catch (e) {
      dlog('[Reaction] fetch error: $e');
      return [];
    }
  }

  Future<Map<String, String>> fetchNicknames(Set<String> uids) async {
    final ids = uids.where((u) => u.isNotEmpty).toList();
    if (ids.isEmpty) return {};
    try {
      final rows = await _sb
          .from('profiles')
          .select('id,nickname')
          .inFilter('id', ids)
          .limit(50);
      final out = <String, String>{};
      for (final row in rows as List) {
        final r = row as Map;
        out['${r['id']}'] = '${r['nickname'] ?? ''}';
      }
      return out;
    } catch (e) {
      dlog('[Reaction] nicknames error: $e');
      return {};
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

  static String reactionCacheKey(String chatId) => 'reactions:$chatId';

  /// Parse cache disk ke map reaksi — defensif terhadap format lama/rusak.
  static Map<String, Map<String, int>> parseCachedReactions(
    Map<String, dynamic> raw,
  ) {
    final out = <String, Map<String, int>>{};
    raw.forEach((mid, v) {
      if (mid.isEmpty || v is! Map) return;
      final per = <String, int>{};
      v.forEach((emoji, c) {
        final n = c is num ? c.toInt() : int.tryParse('$c') ?? 0;
        if ('$emoji'.isNotEmpty && n > 0) per['$emoji'] = n;
      });
      if (per.isNotEmpty) out[mid] = per;
    });
    return out;
  }

  /// Muat reaksi tersimpan untuk tampil instan — stream realtime menimpa
  /// sesudahnya (lazy load, pola sama seperti pesan & daftar online).
  Future<Map<String, Map<String, int>>> loadCachedReactions(
    String chatId,
  ) async {
    try {
      final raw = await MessageCache.instance.loadRawObj(
        reactionCacheKey(chatId),
      );
      return parseCachedReactions(raw);
    } catch (_) {
      return {};
    }
  }

  /// Simpan tiap emission stream (termasuk kosong — emission hanya datang
  /// dari data server asli, jadi aman menimpa).
  Future<void> saveCachedReactions(
    String chatId,
    Map<String, Map<String, int>> m,
  ) async {
    try {
      await MessageCache.instance.saveRawObj(reactionCacheKey(chatId), {
        for (final e in m.entries) e.key: Map<String, dynamic>.from(e.value),
      });
    } catch (_) {}
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

  Future<ToggleResult> toggleStar({
    required String chatType,
    required String chatId,
    required String messageId,
  }) async {
    final me = _sb.auth.currentUser?.id;
    if (me == null || messageId.startsWith('pending-')) {
      return ToggleResult.failed;
    }
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
        return ToggleResult.removed;
      }
      await _sb.from('starred_messages').insert({
        'user_id': me,
        'chat_type': chatType,
        'chat_id': chatId,
        'message_id': messageId,
      });
      return ToggleResult.added;
    } catch (e) {
      dlog('[Star] toggle error: $e');
      return ToggleResult.failed;
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

  static String starredCacheKey(String chatId) => 'starred:$chatId';

  /// Parse cache disk ke set id pesan berbintang — defensif terhadap format
  /// lama/rusak. Menerima bentuk `{'ids': [...]}` (wrapper) agar beda dgn
  /// map kosong; juga toleran terhadap list langsung.
  static Set<String> parseCachedStarred(Map<String, dynamic> raw) {
    final rawIds = raw['ids'];
    if (rawIds is! List) return {};
    final out = <String>{};
    for (final v in rawIds) {
      final id = '$v';
      if (id.isNotEmpty) out.add(id);
    }
    return out;
  }

  /// Muat id pesan berbintang tersimpan untuk tampil INSTAN saat buka chat —
  /// stream realtime menimpa sesudahnya (pola sama seperti reaksi & pesan).
  /// Dulu starred TIDAK punya cache → tiap buka chat bintang "di-load dulu"
  /// menunggu round-trip Supabase.
  Future<Set<String>> loadCachedStarred(String chatId) async {
    try {
      final raw = await MessageCache.instance.loadRawObj(
        starredCacheKey(chatId),
      );
      return parseCachedStarred(raw);
    } catch (_) {
      return {};
    }
  }

  /// Versi SINKRON: langsung dari memori (tanpa await) — dipakai untuk
  /// mengisi bintang SEBELUM frame pertama saat buka chat (anti-glich).
  /// Kosong bila cache belum dimuat di sesi ini (pemanggil fallback async).
  Set<String> peekCachedStarred(String chatId) {
    try {
      final raw = MessageCache.instance.peekRawObj(starredCacheKey(chatId));
      return parseCachedStarred(raw);
    } catch (_) {
      return {};
    }
  }

  /// Muat cache starred ke memori saat bootstrap — supaya `peekCachedStarred`
  /// terisi untuk chat pertama yang dibuka.
  Future<void> preloadCachedStarred(String chatId) async {
    try {
      await MessageCache.instance.preloadRawObj(starredCacheKey(chatId));
    } catch (_) {}
  }

  /// Preload SEMUA cache starred (semua chat) ke memori saat bootstrap —
  /// bintang tampil instan di cold start tanpa menunggu disk per-chat.
  Future<void> preloadAllStarred() async {
    try {
      await MessageCache.instance.preloadObjPrefix('starred:');
    } catch (_) {}
  }

  /// Simpan tiap emission stream. Dibungkus `{'ids': [...]}` supaya kondisi
  /// "tak ada starred" tetap tersimpan (menimpa cache lama) — `saveRawObj`
  /// meng-skip map kosong, sehingga tanpa wrapper bintang yang di-unstar akan
  /// nyangkut di cache.
  Future<void> saveCachedStarred(String chatId, Set<String> ids) async {
    try {
      await MessageCache.instance.saveRawObj(starredCacheKey(chatId), {
        'ids': ids.where((e) => e.isNotEmpty).toList(),
      });
    } catch (_) {}
  }
}
