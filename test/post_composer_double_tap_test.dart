import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    hide Provider, ChangeNotifierProvider, Consumer;

import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/providers/auth_provider.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/theme_provider.dart';
import 'package:chatyuk/providers/timeline_provider.dart';
import 'package:chatyuk/providers/riverpod/timeline_provider.dart';
import 'package:chatyuk/screens/post_composer_screen.dart';
import 'package:chatyuk/services/timeline_service.dart';

import 'test_helper.dart';

/// Guard dobel-tap composer: kasus nyata 2026-09-29 — anggi post "Destination"
/// DUA baris selisih 124ms (ketuk kedua lolos selama `await
/// _ensureRegistered()`, flag `_posting` belum diset).
class MockTimelineService extends Mock implements TimelineService {}

void main() {
  final s = S(isId: true);

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    AppFonts.setLocal(AppFonts.systemKey);
    await initSupabaseForTest();
  });

  tearDownAll(resetFontForTest);

  UserModel registeredUser() => UserModel(
        uid: 'u-tester',
        nickname: 'Tester',
        gender: 'male',
        age: 20,
        country: 'Indonesia',
        city: 'Jakarta',
        ipAddress: '',
        status: 'online',
        avatar: '',
        isRegistered: true,
        loginAt: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        lastSeen: DateTime(2026, 1, 1),
      );

  Widget wrap({
    required AuthProvider auth,
    required TimelineNotifier timeline,
    required ProviderContainer container,
  }) =>
      UncontrolledProviderScope(
        container: container,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider(),
            ),
            ChangeNotifierProvider<ThemeProvider>(
              create: (_) => ThemeProvider(),
            ),
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ],
          child: const MaterialApp(home: PostComposerScreen()),
        ),
      );

  testWidgets('dobel-tap tombol Post → createPost dipanggil tepat 1x',
      (tester) async {
    final auth = AuthProvider(autoInit: false);
    auth.seedProfileForTest(registeredUser());
    final svc = MockTimelineService();
    // RPC lambat → ketukan kedua tiba saat kiriman pertama masih jalan.
    when(() => svc.createPost(
          text: any(named: 'text'),
          imagePaths: any(named: 'imagePaths'),
          imageDims: any(named: 'imageDims'),
          visibility: any(named: 'visibility'),
        )).thenAnswer((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      return {'ok': true, 'id': 'p1'};
    });
    when(() => svc.listPosts(any(),
            limit: any(named: 'limit'),
            cursor: any(named: 'cursor'),
            cursorBoosted: any(named: 'cursorBoosted')))
        .thenAnswer((_) async => []);
    final timeline = TimelineNotifier(service: svc, autoInit: false);
    final container = ProviderContainer(
      overrides: [timelineProvider.overrideWith(() => timeline)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
        wrap(auth: auth, timeline: timeline, container: container));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Destination');
    await tester.pump();

    // Dua ketuk beruntun sebelum pump — seperti tap ganda jari/user.
    final btn = find.widgetWithText(ElevatedButton, s.btnPost);
    await tester.tap(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();

    verify(() => svc.createPost(
          text: 'Destination',
          imagePaths: const [],
          imageDims: const [],
          visibility: any(named: 'visibility'),
        )).called(1);

    // Flush delay 3s load(refresh) + timer lain sebelum teardown.
    await tester.pump(const Duration(seconds: 4));
    auth.dispose();
  });
}
