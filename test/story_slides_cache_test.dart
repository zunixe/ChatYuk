import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/models/story_model.dart';
import 'package:chatyuk/providers/story_provider.dart';
import 'package:chatyuk/services/story_service.dart';

class MockStoryService extends Mock implements StoryService {}

StorySlide slide(String id) => StorySlide(
      id: id,
      authorId: 'a',
      authorName: 'A',
      imagePath: 'chat/$id.jpg',
      createdAt: DateTime.now(),
    );

/// Regresi kasus nyata: author nambah slide (tray: 2) tapi viewer cuma
/// tampil 1 karena cache slide lama dipakai tanpa cek jumlah.
void main() {
  late MockStoryService service;
  late StoryProvider provider;

  setUp(() {
    service = MockStoryService();
    when(() => service.watchStories())
        .thenAnswer((_) => Stream<String>.empty());
    when(() => service.watchStoryViews())
        .thenAnswer((_) => Stream<String>.empty());
    provider = StoryProvider(service: service);
  });

  tearDown(() => provider.dispose());

  test('cache cocok → tanpa fetch ulang', () async {
    when(() => service.fetchSlides('a'))
        .thenAnswer((_) async => [slide('1')]);

    expect((await provider.slidesFor('a', expectedCount: 1)).length, 1);
    expect((await provider.slidesFor('a', expectedCount: 1)).length, 1);
    verify(() => service.fetchSlides('a')).called(1);
  });

  test('tray 2 vs cache 1 → fetch ulang', () async {
    var n = 0;
    when(() => service.fetchSlides('a')).thenAnswer((_) async {
      n++;
      return n == 1 ? [slide('1')] : [slide('1'), slide('2')];
    });

    expect((await provider.slidesFor('a', expectedCount: 1)).length, 1);
    final fresh = await provider.slidesFor('a', expectedCount: 2);
    expect(fresh.length, 2);
    verify(() => service.fetchSlides('a')).called(2);
  });

  test('fetch gagal → cache lama dipertahankan', () async {
    when(() => service.fetchSlides('a'))
        .thenAnswer((_) async => [slide('1')]);
    expect((await provider.slidesFor('a', expectedCount: 1)).length, 1);

    when(() => service.fetchSlides('a')).thenAnswer((_) async => []);
    final res = await provider.slidesFor('a', expectedCount: 2);
    expect(res.length, 1, reason: 'offline tetap tampil 1 slide lama');
  });
}
