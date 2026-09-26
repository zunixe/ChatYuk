import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/models/story_model.dart';
import 'package:chatyuk/providers/story_provider.dart';
import 'package:chatyuk/services/story_service.dart';

class MockStoryService extends Mock implements StoryService {}

StoryTrayItem trayItem(String id, {bool muted = false, bool unseen = true}) =>
    StoryTrayItem(
      authorId: id,
      authorName: 'U-$id',
      hasUnseen: unseen,
      muted: muted,
    );

/// Mute story ala IG: optimistis pindah + transparan, server menyusul.
void main() {
  group('StoryTrayItem', () {
    test('fromMap membaca muted', () {
      final it = StoryTrayItem.fromMap({
        'author_id': 'a',
        'muted': true,
        'has_unseen': true,
      });
      expect(it.muted, isTrue);
      expect(it.hasUnseen, isTrue);
    });

    test('default muted=false (tray lama tanpa kolom)', () {
      expect(StoryTrayItem.fromMap({'author_id': 'a'}).muted, isFalse);
    });

    test('copyWith hanya ubah muted', () {
      const it = StoryTrayItem(authorId: 'a', authorName: 'A', hasUnseen: true);
      final c = it.copyWith(muted: true);
      expect(c.muted, isTrue);
      expect(c.hasUnseen, isTrue);
      expect(c.authorId, 'a');
    });
  });

  group('StoryProvider.toggleStoryMute', () {
    late MockStoryService service;
    late StoryProvider provider;

    setUp(() {
      service = MockStoryService();
      when(() => service.watchStories())
          .thenAnswer((_) => Stream<String>.empty());
      when(() => service.watchStoryViews())
          .thenAnswer((_) => Stream<String>.empty());
      when(() => service.setStoryMuted(any(), any()))
          .thenAnswer((_) async => true);
      provider = StoryProvider(service: service);
    });

    tearDown(() => provider.dispose());

    testWidgets('mute → flag + pindah belakang', (t) async {
      // Tray diisi lewat refresh dengan stub fetchTray.
      when(() => service.fetchTray()).thenAnswer(
        (_) async => [trayItem('a'), trayItem('b'), trayItem('c')],
      );
      await provider.refresh();
      expect(provider.tray.map((e) => e.authorId), ['a', 'b', 'c']);

      await provider.toggleStoryMute('b', true);

      expect(provider.tray.last.authorId, 'b');
      expect(provider.tray.last.muted, isTrue);
      verify(() => service.setStoryMuted('b', true)).called(1);
    });

    testWidgets('unmute → flag hilang', (t) async {
      when(() => service.fetchTray()).thenAnswer(
        (_) async => [trayItem('a', muted: true, unseen: false)],
      );
      await provider.refresh();

      await provider.toggleStoryMute('a', false);

      expect(provider.tray.single.muted, isFalse);
      verify(() => service.setStoryMuted('a', false)).called(1);
    });

    testWidgets('author tak dikenal → no-op', (t) async {
      when(() => service.fetchTray()).thenAnswer((_) async => []);
      await provider.refresh();

      expect(await provider.toggleStoryMute('x', true), isTrue);
      verifyNever(() => service.setStoryMuted(any(), any()));
    });
  });
}
