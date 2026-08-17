import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service timeline: feed postingan, like, comment, share, boost.
class TimelineService {
  final SupabaseClient _sb;
  TimelineService([SupabaseClient? sb]) : _sb = sb ?? Supabase.instance.client;

  String? get uid => _sb.auth.currentUser?.id;

  Future<Map<String, dynamic>> createPost({
    required String text,
    List<String> imagePaths = const [],
    String visibility = 'public',
  }) async {
    final res = await _sb.rpc('create_post', params: {
      'p_text': text,
      'p_image_paths': imagePaths,
      'p_visibility': visibility,
    });
    return _map(res);
  }

  Future<Map<String, dynamic>> toggleLike(String postId) async {
    final res = await _sb.rpc('toggle_post_like', params: {'p_post_id': postId});
    return _map(res);
  }

  Future<Map<String, dynamic>> addComment(String postId, String text) async {
    final res = await _sb.rpc('add_post_comment', params: {
      'p_post_id': postId,
      'p_text': text,
    });
    return _map(res);
  }

  Future<Map<String, dynamic>> sharePost(String postId) async {
    final res = await _sb.rpc('share_post', params: {'p_post_id': postId});
    return _map(res);
  }

  Future<Map<String, dynamic>> boostPost(String postId) async {
    final res = await _sb.rpc('boost_post', params: {'p_post_id': postId});
    return _map(res);
  }

  /// Hapus post milik sendiri (RLS posts_delete_own sudah membatasi).
  Future<void> deletePost(String postId) async {
    await _sb.from('posts').delete().eq('id', postId);
  }

  /// Daftar post. scope 'all' | 'following'.
  /// Cursor keyset: (is_boosted desc, created_at desc) → p_cursor_boosted +
  /// p_cursor. Konsisten dengan ORDER BY di RPC.
  Future<List<Map<String, dynamic>>> listPosts(
    String scope, {
    int limit = 30,
    DateTime? cursor,
    bool cursorBoosted = false,
  }) async {
    try {
      final res = await _sb.rpc('list_posts', params: {
        'p_scope': scope,
        'p_limit': limit,
        'p_cursor': cursor?.toUtc().toIso8601String(),
        'p_cursor_boosted': cursorBoosted,
      });
      final posts = res is Map ? res['posts'] : null;
      if (posts is List) {
        return posts.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (e) {
      debugPrint('[TimelineService] listPosts error: $e');
      return [];
    }
  }

  /// Komentar sebuah post.
  Future<List<Map<String, dynamic>>> comments(String postId) async {
    try {
      final res = await _sb
          .from('post_comments')
          .select()
          .eq('post_id', postId)
          .order('created_at');
      return res.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      debugPrint('[TimelineService] comments error: $e');
      return [];
    }
  }

  /// Biaya boost + limit harian dari server.
  Future<Map<String, dynamic>> pricing() async {
    try {
      final res = await _sb.rpc('timeline_pricing');
      return _map(res);
    } catch (e) {
      debugPrint('[TimelineService] pricing error: $e');
      return {'boost_paid': 50, 'boost_bonus': 150, 'posts_daily_limit': 5};
    }
  }

  /// Realtime tabel posts — SEMUA event (insert/update/delete):
  ///   - insert  → post baru (prepend ke feed)
  ///   - update  → like/comment/share count berubah (trigger DB) → sinkron
  ///     counter di feed semua device
  ///   - delete  → post dihapus author → hilang dari feed semua device
  /// Payload: {'event': 'insert'|'update'|'delete', 'row': {...}}.
  Stream<Map<String, dynamic>> watchNewPosts() {
    final channel = _sb.channel('timeline-posts');
    final controller = StreamController<Map<String, dynamic>>();
    void handle(String event, Map<String, dynamic> row) {
      if (row.isNotEmpty) {
        controller.add({'event': event, 'row': Map<String, dynamic>.from(row)});
      }
    }

    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'posts',
      callback: (payload) {
        final row = payload.eventType == PostgresChangeEvent.delete
            ? payload.oldRecord
            : payload.newRecord;
        handle(payload.eventType.name, row);
      },
    );
    channel.subscribe();
    controller.onCancel = () {
      _sb.removeChannel(channel);
    };
    return controller.stream;
  }

  Map<String, dynamic> _map(dynamic res) {
    if (res is Map) return Map<String, dynamic>.from(res);
    return {};
  }
}
