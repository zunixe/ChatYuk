import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/providers/riverpod/social_provider.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/providers/riverpod/timeline_provider.dart';
import 'package:chatyuk/screens/post_detail_screen.dart';
import 'package:chatyuk/services/social_service.dart';
import 'package:chatyuk/services/timeline_service.dart';
import 'test_helper.dart';

/// Tap notifikasi postingan baru → PostDetailScreen memuat 1 post via
/// get_post (atau empty state bila dihapus/tak boleh dilihat).
class MockTimelineService extends Mock implements TimelineService {}

class MockSocialService extends Mock implements SocialService {}

class TestAuth extends AuthNotifier {
  final UserModel? prof;
  TestAuth(this.prof);
  @override
  AuthData build() =>
      AuthData(profile: prof, uid: prof?.uid, loading: false);
  @override
  UserModel? get profile => prof;
  @override
  String? get uid => prof?.uid;
}

class TestSocial extends SocialNotifier {
  TestSocial();
  @override
  SocialState build() => const SocialState();
}

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

  Map<String, dynamic> postMap() => {
        'id': 'p1',
        'authorId': 'u-author',
        'authorName': 'Author',
        'authorGender': 'male',
        'text': 'Halo timeline',
        'imagePath': '',
        'images': [],
        'imageW': 0,
        'imageH': 0,
        'imageDims': [],
        'visibility': 'public',
        'likeCount': 0,
        'commentCount': 0,
        'shareCount': 0,
        'isBoosted': false,
        'createdAt': DateTime(2026, 9, 29).toIso8601String(),
        // Avatar inline PNG kecil → resolve SINKRON (tanpa fallback
        // ProfileAvatar yang menjadwalkan timer retry 300ms).
        'authorAvatar':
            'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=',
        'isLiked': false,
        'isFollowing': false,
        'isFriend': false,
        'country': 'Indonesia',
      };

  Widget wrap({required Map<String, dynamic>? post}) {
    final svc = MockTimelineService();
    when(() => svc.getPost(any())).thenAnswer((_) async => post);
    final container = ProviderContainer(
      overrides: [
        socialProvider.overrideWith(TestSocial.new),
        timelineProvider.overrideWith(
          () => TimelineNotifier(service: svc, autoInit: false),
        ),
        authProvider.overrideWith(() => TestAuth(registeredUser())),
      ],
    );
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: PostDetailScreen(postId: 'p1')),
    );
  }

  tearDown(() {});

  testWidgets('post ada → teks tampil', (tester) async {
    await tester.pumpWidget(wrap(post: postMap()));
    await tester.pumpAndSettle();
    expect(find.text('Halo timeline'), findsOneWidget);
    expect(find.text(s.titlePostDetail), findsOneWidget);
    // Flush timer retry avatar (300ms) agar teardown bersih.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('post null → empty state', (tester) async {
    await tester.pumpWidget(wrap(post: null));
    await tester.pumpAndSettle();
    expect(find.text(s.postDetailGone), findsOneWidget);
  });
}
