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
}
