import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/providers/riverpod/story_provider.dart';
import 'package:chatyuk/services/story_service.dart';

import 'test_helper.dart';

// Alur kritis 3: tray story → refresh → 1 author tampil.
// Hermetic: StoryService di-mock, tanpa network.

class MockStoryService extends Mock implements StoryService {}

void main() {
  final s = S(isId: true);

  setUpAll(() async {
    await initSupabaseForTest();
    // Prewarm cache media: `StoryNotifier.refresh()` membaca cache disk dulu
    // (MessageCache/MediaDiskCache) sebelum `fetchTrayRaw()` — tanpa prewarm,
    // `waitReady()` menjadwalkan timer pending & refresh tidak pernah selesai.
    await prewarmMediaForTest();
  });

  testWidgets('refresh tray menampilkan author dari service', (tester) async {
    final service = MockStoryService();
    final stories = StreamController<String>.broadcast();
    final views = StreamController<String>.broadcast();
    when(() => service.watchStories()).thenAnswer((_) => stories.stream);
    when(() => service.watchStoryViews()).thenAnswer((_) => views.stream);
    // Kontrak provider sekarang: `fetchTrayRaw()` → List<Map> (bukan
    // `fetchTray()` → List<StoryTrayItem>). Mock harus mengikuti.
    when(() => service.fetchTrayRaw()).thenAnswer(
      (_) async => [
        {
          'author_id': 'u1',
          'author_name': 'Nu1',
          'slide_count': 1,
          'has_unseen': true,
        },
      ],
    );
    final container = ProviderContainer(
      overrides: [
        storyProvider.overrideWith(() => StoryNotifier(service: service)),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final tray = ref.watch(storyProvider).tray;
                return Column(
                  children: [
                    FilledButton(
                      onPressed: () =>
                          ref.read(storyProvider.notifier).refresh(),
                      child: Text(s.btnSave),
                    ),
                    Text('count:${tray.length}'),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );

    // Refresh memuat cache disk + `fetchTrayRaw` (async I/O) → jalankan di
    // runAsync supaya timer/Future benar-benar selesai.
    await tester.tap(find.byType(FilledButton));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text('count:1'), findsOneWidget);
    container.dispose();
    await stories.close();
    await views.close();
  });
}
