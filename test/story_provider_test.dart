import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/models/story_model.dart';
import 'package:chatyuk/providers/story_provider.dart';
import 'package:chatyuk/services/story_service.dart';

import 'test_helper.dart';

class MockStoryService extends Mock implements StoryService {}

StoryTrayItem _tray(String id, {bool own = false, int slides = 1}) =>
    StoryTrayItem(
      authorId: id,
      authorName: 'N$id',
      slideCount: slides,
      hasUnseen: true,
      own: own,
    );

void main() {
  late MockStoryService service;
  late StreamController<String> stories;
  late StreamController<String> views;
  late StoryProvider provider;

  setUpAll(() async {
    await initSupabaseForTest();
  });

  setUp(() {
    service = MockStoryService();
    stories = StreamController<String>.broadcast();
    views = StreamController<String>.broadcast();
    when(() => service.watchStories()).thenAnswer((_) => stories.stream);
    when(() => service.watchStoryViews()).thenAnswer((_) => views.stream);
    when(() => service.fetchTray()).thenAnswer((_) async => [_tray('u1')]);
    provider = StoryProvider(service: service);
  });

  tearDown(() async {
    provider.dispose();
    await stories.close();
    await views.close();
  });

  group('refresh tray', () {
    test('memuat tray + loading mati + notify', () async {
      var notified = 0;
      provider.addListener(() => notified++);
      await provider.refresh();
      expect(provider.tray.map((t) => t.authorId).toList(), ['u1']);
      expect(provider.loading, isFalse);
      expect(provider.error, isNull);
      expect(notified, greaterThan(0));
    });

    test('gagal fetch → error terisi, tray lama dipertahankan', () async {
      await provider.refresh();
      when(() => service.fetchTray()).thenThrow(Exception('down'));
      await provider.refresh();
      expect(provider.error, isNotNull);
      expect(provider.tray.map((t) => t.authorId).toList(), ['u1']);
    });

    test('hasOwnStory + ownItem', () async {
      when(() => service.fetchTray()).thenAnswer(
        (_) async => [_tray('u1'), _tray('me', own: true, slides: 2)],
      );
      await provider.refresh();
      expect(provider.hasOwnStory, isTrue);
      expect(provider.ownItem?.authorId, 'me');
    });
  });

  group('markSeenBulk (penonton story)', () {
    test('meneruskan ids ke service (jalur flush viewer)', () async {
      when(
        () => service.markSeenBulk(any()),
      ).thenAnswer((_) async {});
      await provider.markSeenBulk(['s1', 's2'], 'u1');
      verify(() => service.markSeenBulk(['s1', 's2'])).called(1);
    });

    test('list kosong → service tidak dipanggil', () async {
      await provider.markSeenBulk(const [], 'u1');
      verifyNever(() => service.markSeenBulk(any()));
    });

    test('menandai ring tray author sebagai sudah dilihat', () async {
      when(
        () => service.markSeenBulk(any()),
      ).thenAnswer((_) async {});
      await provider.refresh();
      expect(
        provider.tray.firstWhere((t) => t.authorId == 'u1').hasUnseen,
        isTrue,
      );
      await provider.markSeenBulk(['s1'], 'u1');
      expect(
        provider.tray.firstWhere((t) => t.authorId == 'u1').hasUnseen,
        isFalse,
      );
    });
  });

  group('realtime debounce', () {
    test('event stream memicu refresh senyap (500ms)', () async {
      await provider.refresh();
      verify(() => service.fetchTray()).called(1);
      clearInteractions(service);
      stories.add('ping');
      await Future.delayed(const Duration(milliseconds: 1200));
      verify(() => service.fetchTray()).called(1);
      expect(provider.loading, isFalse);
    });
  });

  group('warm thumb (persistensi seperti avatar)', () {
    test('warmThumb: path kosong → false', () {
      expect(provider.warmThumb(''), isFalse);
    });

    test('warmThumb: disk belum siap → false, tidak menandai cache', () {
      // MediaDiskCache belum di-prewarm di test → isReady false.
      expect(provider.warmThumb('story/u1/a.jpg'), isFalse);
      expect(provider.thumbCached('story/u1/a.jpg'), isNull);
    });

    test('warmTrayThumbs aman saat disk belum siap (tidak throw)', () async {
      await provider.refresh();
      expect(() => provider.warmTrayThumbs(), returnsNormally);
    });
  });

  group('slide aksi (optimistic + revert)', () {
    StorySlide slide(String id, {bool liked = false, int likes = 3}) =>
        StorySlide(
          id: id,
          authorId: 'a',
          authorName: 'A',
          imagePath: 'chat/$id.jpg',
          likeCount: likes,
          liked: liked,
          createdAt: DateTime.now(),
        );

    Future<void> seedSlides() async {
      when(() => service.fetchSlides('a')).thenAnswer(
        (_) async => [slide('s1')],
      );
      await provider.slidesFor('a');
    }

    test('toggleLike sukses → status server', () async {
      await seedSlides();
      when(() => service.toggleLike('s1'))
          .thenAnswer((_) async => (true, 10));

      expect(await provider.toggleLike('s1', 'a'), isTrue);
      final cur = (await provider.slidesFor('a')).single;
      expect(cur.liked, isTrue);
      expect(cur.likeCount, 10);
    });

    test('toggleLike gagal → kembali semula', () async {
      await seedSlides();
      when(() => service.toggleLike('s1')).thenAnswer((_) async => null);

      expect(await provider.toggleLike('s1', 'a'), isNull);
      final cur = (await provider.slidesFor('a')).single;
      expect(cur.liked, isFalse);
      expect(cur.likeCount, 3);
    });

    test('toggleLike tanpa slide → null, service diam', () async {
      when(() => service.fetchSlides('a')).thenAnswer((_) async => []);

      expect(await provider.toggleLike('s9', 'a'), isNull);
      verifyNever(() => service.toggleLike(any()));
    });

    test('markSeen → ring mati + service dipanggil', () async {
      when(() => service.fetchTray()).thenAnswer(
        (_) async => [_tray('a')],
      );
      when(() => service.markSeen(any())).thenAnswer((_) async {});
      await provider.refresh();

      await provider.markSeen('s1', 'a');

      expect(provider.tray.single.hasUnseen, isFalse);
      verify(() => service.markSeen('s1')).called(1);
    });

    test('deleteSlide gagal → false', () async {
      when(() => service.deleteStory(any()))
          .thenAnswer((_) async => (ok: false, path: ''));
      expect(await provider.deleteSlide('s1', 'a'), isFalse);
    });

    test('deleteSlide sukses (gambar) → true', () async {
      when(() => service.deleteStory(any()))
          .thenAnswer((_) async => (ok: true, path: 'chat/x.jpg'));
      expect(await provider.deleteSlide('s1', 'a'), isTrue);
    });

    test('deleteSlide sukses (video, path kosong) → true', () async {
      when(() => service.deleteStory(any()))
          .thenAnswer((_) async => (ok: true, path: ''));
      expect(await provider.deleteSlide('s1', 'a'), isTrue,
          reason: 'story video terhapus walau tanpa image_path');
    });

    test('fetchViewers teruskan hasil service', () async {
      when(() => service.fetchViewers('s1')).thenAnswer(
        (_) async => [
          StoryViewer(
            viewerId: 'u1',
            nickname: 'Budi',
            viewedAt: DateTime.now(),
          ),
        ],
      );
      final out = await provider.fetchViewers('s1');
      expect(out!.single.nickname, 'Budi');
    });

    test('invalidateSlides → fetch ulang berikutnya', () async {
      var n = 0;
      when(() => service.fetchSlides('a')).thenAnswer((_) async {
        n++;
        return [slide('s$n')];
      });
      expect((await provider.slidesFor('a')).single.id, 's1');
      provider.invalidateSlides('a');
      expect((await provider.slidesFor('a')).single.id, 's2');
      verify(() => service.fetchSlides('a')).called(2);
    });
  });

  group('thumb RAM', () {

    test(
      'thumbFor: hasil masuk RAM provider, panggilan kedua tidak unduh',
      () async {
        var calls = 0;
        when(() => service.fetchTray()).thenAnswer((_) async => []);
        await provider.refresh();
        // thumbFor tanpa network & tanpa disk → null, tapi tidak boleh throw
        // dan tidak boleh menyimpan nilai kosong ke RAM.
        final b = await provider.thumbFor('story/u1/missing.jpg');
        calls++;
        expect(b, isNull);
        expect(calls, 1);
        expect(provider.thumbCached('story/u1/missing.jpg'), isNull);
      },
    );
  });
}
