import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:phosphor_icons/phosphor_icons.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/providers/auth_provider.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/timeline_provider.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/services/timeline_service.dart';
import 'package:chatyuk/widgets/post_card.dart';

import 'test_helper.dart';

/// Fase 5 — PostCard: render + perilaku kunci (logic-only, tanpa jaringan).
class MockTimelineService extends Mock implements TimelineService {}

class MockAuthService extends Mock implements AuthService {}

Map<String, dynamic> _post({
  String id = 'p1',
  String author = 'Budi',
  String text = 'Halo dunia',
  int likes = 0,
  int comments = 0,
  int shares = 0,
  bool boosted = false,
  bool friend = false,
  bool liked = false,
}) =>
    {
      'id': id,
      'authorId': 'a1',
      'authorName': author,
      'text': text,
      'likeCount': likes,
      'commentCount': comments,
      'shareCount': shares,
      'isBoosted': boosted,
      'isFriend': friend,
      'isLiked': liked,
      'isFollowing': false,
      // Avatar inline PNG kecil → _AuthorAvatar resolve SINKRON (tak
      // fallback ke ProfileAvatar yang menjadwalkan timer retry 300ms).
      'authorAvatar':
          'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };

void main() {
  late MockTimelineService timeline;
  late MockAuthService auth;

  setUpAll(() async {
    await initSupabaseForTest();
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    timeline = MockTimelineService();
    auth = MockAuthService();
    when(() => timeline.watchNewPosts())
        .thenAnswer((_) => const Stream.empty());
    when(() => timeline.pricing()).thenAnswer((_) async => {});
    when(() => timeline.comments(any())).thenAnswer((_) async => []);
    when(() => auth.uid).thenReturn('me');
    when(() => auth.currentUser).thenReturn(null);
    when(() => auth.isSignedIn).thenReturn(true);
    when(() => auth.isAnonymous).thenReturn(false);
    when(() => auth.onMyProfileUpdates())
        .thenAnswer((_) => const Stream.empty());
  });

  Future<void> pump(WidgetTester tester, Map<String, dynamic> post) async {
    final locale = LocaleProvider();
    final tp = TimelineProvider(service: timeline, autoInit: false);
    final ap = AuthProvider(authService: auth, autoInit: false);
    addTearDown(() {
      tp.dispose();
      ap.dispose();
      locale.dispose();
    });
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: locale),
          ChangeNotifierProvider.value(value: tp),
          ChangeNotifierProvider.value(value: ap),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: PostCard(post: post)),
          ),
        ),
      ),
    );
    await tester.pump();
    // Buang timer yang mungkin dijadwalkan provider/widget (anti-invariant).
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('render menampilkan nama author & teks post', (tester) async {
    await pump(tester, _post(author: 'Budi', text: 'Isi postingan uji'));
    expect(find.text('Budi'), findsOneWidget);
    expect(find.textContaining('Isi postingan uji'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('menampilkan jumlah like/komentar/share', (tester) async {
    await pump(tester, _post(likes: 7, comments: 3, shares: 2));
    expect(find.text('7'), findsWidgets);
    expect(find.text('3'), findsWidgets);
    expect(find.text('2'), findsWidgets);
  });

  testWidgets('post tanpa teks tetap render tanpa error', (tester) async {
    final p = _post(text: '');
    await pump(tester, p);
    expect(tester.takeException(), isNull);
  });

  testWidgets('post boosted & friend menampilkan badge tanpa error',
      (tester) async {
    await pump(tester, _post(boosted: true, friend: true));
    expect(tester.takeException(), isNull);
  });

  testWidgets('author id == uid sendiri dirender (isAuthor)', (tester) async {
    final p = _post()..['authorId'] = 'me';
    await pump(tester, p);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap tombol like → delegasi toggleLike ke TimelineProvider',
      (tester) async {
    when(() => timeline.toggleLike('p1')).thenAnswer(
      (_) async => {'liked': true, 'likeCount': 8},
    );
    await pump(tester, _post(likes: 7));

    // Tap ikon hati (aksi pertama) — cari InkWell pertama di baris aksi.
    await tester.tap(find.byIcon(PhosphorIconsRegular.heart).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    verify(() => timeline.toggleLike('p1')).called(1);
  });
}
