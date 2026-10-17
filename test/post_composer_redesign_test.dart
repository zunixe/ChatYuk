import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/models/auth_data.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/providers/riverpod/timeline_provider.dart';
import 'package:chatyuk/screens/post_composer_screen.dart';
import 'package:chatyuk/services/timeline_service.dart';

import 'test_helper.dart';

/// Mengunci redesign composer "Postingan baru" (UI saja).
class MockTimelineService extends Mock implements TimelineService {}

class TestAuth extends AuthNotifier {
  final UserModel? prof;
  TestAuth(this.prof);
  @override
  AuthData build() => AuthData(profile: prof, uid: prof?.uid, loading: false);
  @override
  UserModel? get profile => prof;
  @override
  String? get uid => prof?.uid;
}

void main() {
  final s = S(isId: true);

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    AppFonts.setLocal(AppFonts.systemKey);
    await initSupabaseForTest();
    await prewarmMediaForTest();
  });

  tearDownAll(resetFontForTest);

  UserModel user({List<String> hashtags = const []}) => UserModel(
        uid: 'u-test',
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
        hashtags: hashtags,
      );

  Finder textOnly(String t) =>
      find.byWidgetPredicate((w) => w is Text && w.data == t);

  Future<void> flush(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
  }

  Future<ProviderContainer> pumpComposer(
    WidgetTester tester, {
    UserModel? profile,
  }) async {
    final svc = MockTimelineService();
    when(() => svc.watchNewPosts()).thenAnswer((_) => const Stream.empty());
    when(() => svc.pricing()).thenAnswer((_) async => {});
    when(() => svc.listPosts(any(),
            limit: any(named: 'limit'),
            cursor: any(named: 'cursor'),
            cursorBoosted: any(named: 'cursorBoosted')))
        .thenAnswer((_) async => []);
    final container = ProviderContainer(overrides: [
      timelineProvider.overrideWith(
          () => TimelineNotifier(service: svc, autoInit: false)),
      authProvider.overrideWith(() => TestAuth(profile ?? user())),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PostComposerScreen()),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('tombol Posting nonaktif saat kosong, aktif setelah isi',
      (tester) async {
    await pumpComposer(tester);
    expect(find.text(s.composerTitleNew), findsOneWidget);

    ElevatedButton btn() =>
        tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(btn().onPressed, isNull, reason: 'kosong → nonaktif');

    await tester.enterText(find.byType(TextField).first, 'halo');
    await tester.pump();
    expect(btn().onPressed, isNotNull, reason: 'ada teks → aktif');
    await flush(tester);
  });

  testWidgets('counter n/500 + formatter membatasi 500', (tester) async {
    await pumpComposer(tester);
    expect(find.text('0/500'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'halo');
    await tester.pump();
    expect(find.text('4/500'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'a' * 700);
    await tester.pump();
    final tf = tester.widget<TextField>(find.byType(TextField).first);
    expect(tf.controller!.text.length, lessThanOrEqualTo(500));
    expect(find.text('500/500'), findsOneWidget);
    await flush(tester);
  });

  testWidgets('chip visibilitas → sheet → pilihan tersimpan', (tester) async {
    await pumpComposer(tester);
    expect(find.text(s.visPublic), findsOneWidget);

    await tester.tap(find.text(s.visPublic));
    await tester.pumpAndSettle();
    expect(find.text(s.titleWhoCanReply), findsOneWidget);

    await tester.tap(find.text(s.visFollowers));
    await tester.pumpAndSettle();
    expect(find.text(s.titleWhoCanReply), findsNothing);
    expect(find.text(s.visFollowers), findsOneWidget);
    await flush(tester);
  });

  testWidgets('saran hashtag menambahkan #tag ke teks', (tester) async {
    await pumpComposer(
      tester,
      profile: user(hashtags: const ['futsal', 'musik']),
    );
    expect(textOnly('#futsal'), findsOneWidget);

    await tester.tap(textOnly('#futsal'));
    await tester.pump();
    final tf = tester.widget<TextField>(find.byType(TextField).first);
    expect(tf.controller!.text, '#futsal');
    // Sudah ada di teks → chip saran hilang (EditableText bukan Text widget).
    expect(textOnly('#futsal'), findsNothing);
    await flush(tester);
  });

  testWidgets('tutup saat ada isi → dialog "Buang postingan?"',
      (tester) async {
    await pumpComposer(tester);
    await tester.enterText(find.byType(TextField).first, 'draft');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(find.text(s.composerDiscardTitle), findsOneWidget);
    expect(find.text(s.btnDiscard), findsOneWidget);
    // Tutup dialog agar timer/animation bersih.
    await tester.tap(find.text(s.btnCancel));
    await tester.pumpAndSettle();
    await flush(tester);
  });

  testWidgets('TextField benar-benar tanpa box/latar (filled=false)',
      (tester) async {
    await pumpComposer(tester);
    final tf = tester.widget<TextField>(find.byType(TextField).first);
    // Tema global punya inputDecorationTheme filled=true (radius 12) → WAJIB
    // ditimpa, kalau tidak muncul "kotak belakang rounded" di balik hint.
    expect(tf.decoration!.filled, isFalse);
    expect(tf.decoration!.border, InputBorder.none);
    await flush(tester);
  });

  testWidgets('tidak overflow di layar 360', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpComposer(
      tester,
      profile: user(hashtags: const ['futsal', 'musik', 'gaming']),
    );
    await tester.enterText(find.byType(TextField).first, 'tes layar sempit');
    await tester.pump();
    expect(tester.takeException(), isNull);
    await flush(tester);
  });
}
