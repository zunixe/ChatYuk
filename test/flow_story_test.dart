import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/models/story_model.dart';
import 'package:chatyuk/providers/story_provider.dart';
import 'package:chatyuk/services/story_service.dart';

// Alur kritis 3: tray story → refresh → 1 author tampil.
// Hermetic: StoryService di-mock, tanpa network.

class MockStoryService extends Mock implements StoryService {}

void main() {
  final s = S(isId: true);

  testWidgets('refresh tray menampilkan author dari service', (tester) async {
    final service = MockStoryService();
    final stories = StreamController<String>.broadcast();
    final views = StreamController<String>.broadcast();
    when(() => service.watchStories()).thenAnswer((_) => stories.stream);
    when(() => service.watchStoryViews()).thenAnswer((_) => views.stream);
    when(() => service.fetchTray()).thenAnswer(
      (_) async => [
        StoryTrayItem(
          authorId: 'u1',
          authorName: 'Nu1',
          slideCount: 1,
          hasUnseen: true,
        ),
      ],
    );
    final provider = StoryProvider(service: service);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<StoryProvider>.value(
          value: provider,
          child: Scaffold(
            body: Builder(
              builder: (context) {
                final tray = context.watch<StoryProvider>().tray;
                return Column(
                  children: [
                    FilledButton(
                      onPressed: () => context.read<StoryProvider>().refresh(),
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

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('count:1'), findsOneWidget);
    provider.dispose();
    await stories.close();
    await views.close();
  });
}
