import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:chatyuk/services/social_service.dart';
import 'package:chatyuk/services/story_service.dart';

import 'supabase_test_client.dart';

/// Semi-integrasi `StoryService` + `SocialService` (HTTP palsu) — memverifikasi
/// nama RPC + params yang benar-benar dikirim ke PostgREST, termasuk jalur
/// fallback yang selama ini hanya diasumsikan benar.
void main() {
  group('StoryService (I/O palsu)', () {
    test('createStory: semua params teks & clamp nilai terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/create_story', (_) => {'id': 'story-1'});
      final svc = StoryService(fakeSupabaseClient(handler: handler));

      final id = await svc.createStory(
        imagePath: 'story/u1/a.jpg',
        textOverlay: 'Halo',
        textX: 0.25,
        textY: 0.75,
        textColor: 3,
        textSize: 2,
        textScale: 1.5,
        textBg: true,
        visibility: 'friends',
      );

      expect(id, 'story-1');
      final p = rpcParamsOf(handler, 'create_story');
      expect(p['p_image_path'], 'story/u1/a.jpg');
      expect(p['p_text_overlay'], 'Halo');
      expect(p['p_text_x'], 0.25);
      expect(p['p_text_y'], 0.75);
      expect(p['p_text_color'], 3);
      expect(p['p_text_size'], 2);
      expect(p['p_text_scale'], 1.5);
      expect(p['p_text_bg'], true);
      expect(p['p_visibility'], 'friends');
    });

    test('markSeenBulk: daftar id terkirim sekali (1 round-trip)', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/mark_story_seen_bulk', (_) => []);
      final svc = StoryService(fakeSupabaseClient(handler: handler));

      await svc.markSeenBulk(['s1', 's2', 's3']);

      final p = rpcParamsOf(handler, 'mark_story_seen_bulk');
      expect(p['p_ids'], ['s1', 's2', 's3']);
      // Hanya 1 request bulk — tidak ada fallback per-id.
      expect(
        handler.captured.where((r) => r.url.path.contains('/rpc/')).length,
        1,
      );
    });

    test('markSeenBulk: daftar kosong → tidak ada request', () async {
      final handler = FakeSupabaseHandler();
      final svc = StoryService(fakeSupabaseClient(handler: handler));

      await svc.markSeenBulk(const []);

      expect(handler.captured, isEmpty);
    });

    test('deleteStory: p_story_id terkirim + parsing image_path', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/delete_story',
        (_) => {'image_path': 'story/u1/x.jpg'},
      );
      final svc = StoryService(fakeSupabaseClient(handler: handler));

      final path = await svc.deleteStory('story-9');

      expect(path, 'story/u1/x.jpg');
      expect(rpcParamsOf(handler, 'delete_story')['p_story_id'], 'story-9');
    });

    test('markSeen: p_story_id terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/mark_story_seen', (_) => []);
      final svc = StoryService(fakeSupabaseClient(handler: handler));

      await svc.markSeen('story-2');

      expect(rpcParamsOf(handler, 'mark_story_seen')['p_story_id'], 'story-2');
    });

    test('toggleLike: story id terkirim + hasil like diparsing', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/toggle_story_like',
        (_) => {'ok': true, 'liked': true, 'count': 4},
      );
      final svc = StoryService(fakeSupabaseClient(handler: handler));

      final result = await svc.toggleLike('story-3');

      expect(result, (true, 4));
      expect(
        rpcParamsOf(handler, 'toggle_story_like')['p_story_id'],
        'story-3',
      );
    });

    test('fetchViewers: p_story_id terkirim + list dipetakan', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/story_viewers', (_) => [
            {
              'viewer_id': 'u-1',
              'nickname': 'Budi',
              'avatar': 'avatar/u-1.jpg',
              'viewed_at': '2026-09-23T10:15:00.000Z',
              'liked': true,
            },
            {
              'viewer_id': 'u-2',
              'nickname': 'Sari',
              'avatar': '',
              'viewed_at': '2026-09-23T09:00:00.000Z',
              'liked': false,
            },
          ]);
      final svc = StoryService(fakeSupabaseClient(handler: handler));

      final viewers = await svc.fetchViewers('story-7');

      expect(viewers, isNotNull);
      expect(viewers!.length, 2);
      expect(viewers.first.viewerId, 'u-1');
      expect(viewers.first.nickname, 'Budi');
      expect(viewers.first.liked, isTrue);
      expect(viewers[1].liked, isFalse);
      expect(
        rpcParamsOf(handler, 'story_viewers')['p_story_id'],
        'story-7',
      );
    });

    test('fetchViewers: daftar kosong → [] (bukan null)', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/story_viewers', (_) => []);
      final svc = StoryService(fakeSupabaseClient(handler: handler));

      final viewers = await svc.fetchViewers('story-8');

      expect(viewers, isNotNull);
      expect(viewers, isEmpty);
    });

    test('fetchViewers: RPC error → null (bukan [] yang menyamar kosong)',
        () async {
      final handler = FakeSupabaseHandler();
      // Status non-200 → client melempar → service mengembalikan null.
      handler.on(
        '/rest/v1/rpc/story_viewers',
        (req) => http.Response('{"message":"Unauthorized"}', 401, request: req),
      );
      final svc = StoryService(fakeSupabaseClient(handler: handler));

      final viewers = await svc.fetchViewers('story-9');

      expect(viewers, isNull,
          reason: 'gagal harus beda dari "belum ada penonton"');
    });
  });

  group('SocialService (I/O palsu)', () {
    test('followUser: p_followee terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/follow_user', (_) => {'status': 'following'});
      final svc = SocialService(fakeSupabaseClient(handler: handler));

      final res = await svc.followUser('u-2');

      expect(res['status'], 'following');
      expect(rpcParamsOf(handler, 'follow_user')['p_followee'], 'u-2');
    });

    test('sendFriendRequest: p_to terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on(
        '/rest/v1/rpc/send_friend_request',
        (_) => {'status': 'pending'},
      );
      final svc = SocialService(fakeSupabaseClient(handler: handler));

      final res = await svc.sendFriendRequest('u-3');

      expect(res['status'], 'pending');
      expect(rpcParamsOf(handler, 'send_friend_request')['p_to'], 'u-3');
    });

    test('respondFriendRequest: request_id + accept terkirim', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/respond_friend_request', (_) => {'ok': true});
      final svc = SocialService(fakeSupabaseClient(handler: handler));

      await svc.respondFriendRequest(42, false);

      final p = rpcParamsOf(handler, 'respond_friend_request');
      expect(p['p_request_id'], 42);
      expect(p['p_accept'], false);
    });

    test('subscribeCreator: periods default 1 bila tidak disebut', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/subscribe_creator', (_) => {'ok': true});
      final svc = SocialService(fakeSupabaseClient(handler: handler));

      await svc.subscribeCreator('creator-1');

      final p = rpcParamsOf(handler, 'subscribe_creator');
      expect(p['p_creator'], 'creator-1');
      expect(p['p_periods'], 1);
    });

    test('clearAnonSocial: RPC tanpa params (guard logout)', () async {
      final handler = FakeSupabaseHandler();
      handler.on('/rest/v1/rpc/clear_anon_social', (_) => []);
      final svc = SocialService(fakeSupabaseClient(handler: handler));

      await svc.clearAnonSocial();

      final p = rpcParamsOf(handler, 'clear_anon_social');
      expect(p, isEmpty);
    });
  });
}
