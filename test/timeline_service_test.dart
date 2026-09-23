import 'package:flutter_test/flutter_test.dart';

import 'package:chatyuk/services/timeline_service.dart';

import 'supabase_test_client.dart';

/// Fase 3 — TimelineService: verifikasi nama RPC + params yang benar-benar
/// dikirim ke PostgREST (tanpa jaringan), via `FakeSupabaseHandler`.
/// Logic-only: tidak menyentuh realtime WebSocket.
void main() {
  late FakeSupabaseHandler handler;
  late TimelineService svc;

  setUp(() {
    handler = FakeSupabaseHandler();
    svc = TimelineService(fakeSupabaseClient(handler: handler));
  });

  group('createPost', () {
    test('kirim RPC create_post dengan p_text/p_image_paths/p_visibility', () async {
      handler.on('create_post', (_) => {'id': 'p1'});
      final out = await svc.createPost(
        text: 'halo',
        imagePaths: ['posts/a.jpg'],
        visibility: 'friends',
      );
      expect(out['id'], 'p1');
      final params = rpcParamsOf(handler, 'create_post');
      expect(params['p_text'], 'halo');
      expect(params['p_image_paths'], ['posts/a.jpg']);
      expect(params['p_visibility'], 'friends');
    });

    test('default visibility public & imagePaths kosong', () async {
      handler.on('create_post', (_) => {'id': 'p2'});
      await svc.createPost(text: 'x');
      final params = rpcParamsOf(handler, 'create_post');
      expect(params['p_visibility'], 'public');
      expect(params['p_image_paths'], isEmpty);
    });

    test('imagePaths base64 → ArgumentError sebelum RPC', () async {
      handler.on('create_post', (_) => {'id': 'p3'});
      await expectLater(
        svc.createPost(text: 'x', imagePaths: ['/9j/4AAQSkZJRg==']),
        throwsArgumentError,
      );
      expect(handler.captured, isEmpty,
          reason: 'base64 tidak boleh sampai ke server');
    });
  });

  group('toggleLike / boost / share', () {
    test('toggleLike → RPC toggle_post_like dengan p_post_id', () async {
      handler.on('toggle_post_like', (_) => {'liked': true, 'likeCount': 5});
      final out = await svc.toggleLike('post-9');
      expect(out['liked'], true);
      expect(rpcParamsOf(handler, 'toggle_post_like')['p_post_id'], 'post-9');
    });

    test('boostPost → RPC boost_post', () async {
      handler.on('boost_post', (_) => {'ok': true});
      await svc.boostPost('post-9');
      expect(rpcParamsOf(handler, 'boost_post')['p_post_id'], 'post-9');
    });

    test('sharePost → RPC share_post', () async {
      handler.on('share_post', (_) => {'shareCount': 2});
      await svc.sharePost('post-9');
      expect(rpcParamsOf(handler, 'share_post')['p_post_id'], 'post-9');
    });
  });

  group('listPosts', () {
    test('unwrap {posts:[...]} & kirim cursor keyset', () async {
      handler.on('list_posts', (_) => {
            'posts': [
              {'id': 'a'},
              {'id': 'b'},
            ]
          });
      final out = await svc.listPosts('following', limit: 10, cursorBoosted: true);
      expect(out.length, 2);
      final params = rpcParamsOf(handler, 'list_posts');
      expect(params['p_scope'], 'following');
      expect(params['p_limit'], 10);
      expect(params['p_cursor_boosted'], true);
    });

    test('res bukan map / tanpa posts → []', () async {
      handler.on('list_posts', (_) => []);
      expect(await svc.listPosts('all'), isEmpty);
    });

    test('cursor null → p_cursor null', () async {
      handler.on('list_posts', (_) => {'posts': []});
      await svc.listPosts('all');
      expect(rpcParamsOf(handler, 'list_posts')['p_cursor'], isNull);
    });
  });

  group('comments', () {
    test('unwrap list komentar', () async {
      handler.on('list_post_comments', (_) => [
            {'id': 1},
            {'id': 2},
          ]);
      final out = await svc.comments('post-1');
      expect(out.length, 2);
      expect(
        rpcParamsOf(handler, 'list_post_comments')['p_post_id'],
        'post-1',
      );
    });

    test('res bukan list → []', () async {
      handler.on('list_post_comments', (_) => {'x': 1});
      expect(await svc.comments('post-1'), isEmpty);
    });
  });

  group('comment interactions', () {
    test('toggleCommentLike → p_comment_id', () async {
      handler.on('toggle_comment_like', (_) => {'liked': true});
      final out = await svc.toggleCommentLike(42);
      expect(out['liked'], true);
      expect(rpcParamsOf(handler, 'toggle_comment_like')['p_comment_id'], 42);
    });

    test('replyComment → p_post_id/p_parent_id/p_text', () async {
      handler.on('reply_post_comment', (_) => {'id': 7});
      await svc.replyComment('post-1', 3, 'balas');
      final p = rpcParamsOf(handler, 'reply_post_comment');
      expect(p['p_post_id'], 'post-1');
      expect(p['p_parent_id'], 3);
      expect(p['p_text'], 'balas');
    });

    test('shareComment → p_comment_id', () async {
      handler.on('share_post_comment', (_) => {'shareCount': 1});
      await svc.shareComment(9);
      expect(rpcParamsOf(handler, 'share_post_comment')['p_comment_id'], 9);
    });
  });

  group('pricing', () {
    test('kirim RPC timeline_pricing & map hasil', () async {
      handler.on('timeline_pricing', (_) => {
            'boost_paid': 60,
            'boost_bonus': 150,
            'posts_daily_limit': 5,
          });
      final out = await svc.pricing();
      expect(out['boost_paid'], 60);
    });

    test('server error → fallback default (bukan crash)', () async {
      // Tanpa route → default [] (200). RPC pricing fallback bila hasil bukan
      // map. Paksa handler melempar untuk menguji catch.
      final h = FakeSupabaseHandler()
        ..on('timeline_pricing', (_) => throw Exception('down'));
      final s = TimelineService(fakeSupabaseClient(handler: h));
      final out = await s.pricing();
      expect(out['boost_paid'], 50);
      expect(out['posts_daily_limit'], 5);
    });
  });

  group('deletePost', () {
    test('DELETE ke tabel posts dengan filter id', () async {
      handler.on('posts', (_) => {});
      await svc.deletePost('post-42');
      final req = handler.captured.firstWhere((r) => r.method == 'DELETE');
      expect(req.url.path.contains('/rest/v1/posts'), isTrue);
      expect(req.url.query.contains('id=eq.post-42'), isTrue);
    });
  });
}
