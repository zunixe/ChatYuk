import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/providers/timeline_provider.dart';
import 'package:chatyuk/services/timeline_service.dart';

import 'test_helper.dart';

class MockTimelineService extends Mock implements TimelineService {}

Map<String, dynamic> _post(String id, {String createdAt = '2026-01-02T03:04:05Z'}) => {
      'id': id,
      'authorId': 'a1',
      'authorName': 'Budi',
      'text': 'halo $id',
      'likeCount': 0,
      'commentCount': 0,
      'shareCount': 0,
      'isBoosted': false,
      'createdAt': createdAt,
      'authorAvatar': '',
      'isLiked': false,
      'isFollowing': false,
      'isFriend': false,
    };

void main() {
  late MockTimelineService service;

  setUpAll(() async {
    await initSupabaseForTest();
  });

  setUp(() {
    service = MockTimelineService();
    when(() => service.watchNewPosts())
        .thenAnswer((_) => const Stream.empty());
    when(() => service.pricing()).thenAnswer((_) async => {});
    when(() => service.comments(any())).thenAnswer((_) async => []);
  });

  group('load refresh', () {
    test('fetch sukses mengisi feed + matikan loading', () async {
      when(() => service.listPosts(any(),
              cursor: any(named: 'cursor'),
              cursorBoosted: any(named: 'cursorBoosted')))
          .thenAnswer((_) async => [_post('p1'), _post('p2')]);
      final tp = TimelineProvider(service: service);
      await tp.load('all', refresh: true);
      expect(tp.loading, isFalse);
      expect(tp.fetchFailed, isFalse);
      expect(tp.posts.map((p) => p['id']), ['p1', 'p2']);
      // <30 item = ujung feed.
      expect(tp.hasMore, isFalse);
      tp.dispose();
    });

    test('server jawab kosong saat refresh → feed dikosongkan, bukan error',
        () async {
      when(() => service.listPosts(any(),
              cursor: any(named: 'cursor'),
              cursorBoosted: any(named: 'cursorBoosted')))
          .thenAnswer((_) async => [_post('p1')]);
      final tp = TimelineProvider(service: service);
      await tp.load('all', refresh: true);
      expect(tp.posts, isNotEmpty);

      when(() => service.listPosts(any(),
              cursor: any(named: 'cursor'),
              cursorBoosted: any(named: 'cursorBoosted')))
          .thenAnswer((_) async => []);
      await tp.load('all', refresh: true);
      expect(tp.posts, isEmpty);
      expect(tp.fetchFailed, isFalse);
      tp.dispose();
    });

    test('network error → feed lama dipertahankan + fetchFailed', () async {
      when(() => service.listPosts(any(),
              cursor: any(named: 'cursor'),
              cursorBoosted: any(named: 'cursorBoosted')))
          .thenAnswer((_) async => [_post('p1')]);
      final tp = TimelineProvider(service: service);
      await tp.load('all', refresh: true);
      expect(tp.posts.length, 1);

      when(() => service.listPosts(any(),
              cursor: any(named: 'cursor'),
              cursorBoosted: any(named: 'cursorBoosted')))
          .thenThrow(Exception('socket mati'));
      await tp.load('all', refresh: true);
      // Offline-safe: data lama tidak terhapus, flag error menyala.
      expect(tp.posts.length, 1);
      expect(tp.fetchFailed, isTrue);
      expect(tp.loading, isFalse);
      tp.dispose();
    });

    test('refresh selalu fetch ulang (instan dari cache, server menyusul)',
        () async {
      when(() => service.listPosts(any(),
              cursor: any(named: 'cursor'),
              cursorBoosted: any(named: 'cursorBoosted')))
          .thenAnswer((_) async => [_post('p1')]);
      final tp = TimelineProvider(service: service);
      await tp.load('all', refresh: true);
      expect(tp.posts.map((p) => p['id']), ['p1']);

      when(() => service.listPosts(any(),
              cursor: any(named: 'cursor'),
              cursorBoosted: any(named: 'cursorBoosted')))
          .thenAnswer((_) async => [_post('p2')]);
      await tp.load('all', refresh: true);
      // Feed diganti atomik dengan hasil fetch terbaru.
      expect(tp.posts.map((p) => p['id']), ['p2']);
      verify(() => service.listPosts(any(),
          cursor: any(named: 'cursor'),
          cursorBoosted: any(named: 'cursorBoosted'))).called(2);
      tp.dispose();
    });
  });

  group('cache komentar (TTL)', () {
    test('cacheComments → isCommentsFresh true, hasCommentsCache true', () {
      final tp = TimelineProvider(service: service);
      expect(tp.hasCommentsCache('p1'), isFalse);
      expect(tp.isCommentsFresh('p1'), isFalse);

      tp.cacheComments('p1', [
        {'id': 1, 'text': 'hai'},
      ]);

      expect(tp.hasCommentsCache('p1'), isTrue);
      expect(tp.isCommentsFresh('p1'), isTrue);
      expect(tp.getCachedComments('p1')!.length, 1);
      tp.dispose();
    });

    test('addCommentToCache menambah tanpa mengubah TTL freshness', () {
      final tp = TimelineProvider(service: service);
      tp.cacheComments('p1', [
        {'id': 1},
      ]);
      tp.addCommentToCache('p1', {'id': 2});
      expect(tp.getCachedComments('p1')!.length, 2);
      expect(tp.isCommentsFresh('p1'), isTrue);
      tp.dispose();
    });

    test('removeCommentFromCache menghapus id tertentu', () {
      final tp = TimelineProvider(service: service);
      tp.cacheComments('p1', [
        {'id': 1},
        {'id': 2},
      ]);
      tp.removeCommentFromCache('p1', 1);
      expect(tp.getCachedComments('p1')!.map((c) => c['id']), [2]);
      tp.dispose();
    });

    test('resetCache mengosongkan cache + timestamp komentar', () {
      final tp = TimelineProvider(service: service);
      tp.cacheComments('p1', [
        {'id': 1},
      ]);
      tp.resetCache();
      expect(tp.hasCommentsCache('p1'), isFalse);
      expect(tp.isCommentsFresh('p1'), isFalse);
      tp.dispose();
    });
  });

  group('realtime update — guard notify', () {
    test('update post yang TIDAK ada di feed → tidak notify', () async {
      when(() => service.listPosts(any(),
              cursor: any(named: 'cursor'),
              cursorBoosted: any(named: 'cursorBoosted')))
          .thenAnswer((_) async => [_post('p1')]);
      final tp = TimelineProvider(service: service);
      await tp.load('all', refresh: true);

      var notifies = 0;
      tp.addListener(() => notifies++);
      // Event update untuk post yang tidak ada di feed.
      tp.debugOnNewPost({
        'event': 'update',
        'row': {'id': 'lain', 'like_count': 9},
      });
      expect(notifies, 0, reason: 'post tak ada di feed → jangan rebuild');
      tp.dispose();
    });

    test('update post ADA di feed dengan nilai berubah → notify', () async {
      when(() => service.listPosts(any(),
              cursor: any(named: 'cursor'),
              cursorBoosted: any(named: 'cursorBoosted')))
          .thenAnswer((_) async => [_post('p1')]);
      final tp = TimelineProvider(service: service);
      await tp.load('all', refresh: true);

      var notifies = 0;
      tp.addListener(() => notifies++);
      tp.debugOnNewPost({
        'event': 'update',
        'row': {'id': 'p1', 'like_count': 5},
      });
      expect(notifies, 1);
      expect(tp.posts.first['likeCount'], 5);
      tp.dispose();
    });

    test('update tanpa perubahan nilai → tidak notify (no-op)', () async {
      when(() => service.listPosts(any(),
              cursor: any(named: 'cursor'),
              cursorBoosted: any(named: 'cursorBoosted')))
          .thenAnswer((_) async => [_post('p1')]);
      final tp = TimelineProvider(service: service);
      await tp.load('all', refresh: true);

      var notifies = 0;
      tp.addListener(() => notifies++);
      // Nilai sama dengan yang sudah ada (likeCount 0).
      tp.debugOnNewPost({
        'event': 'update',
        'row': {'id': 'p1', 'like_count': 0},
      });
      expect(notifies, 0);
      tp.dispose();
    });
  });
}
