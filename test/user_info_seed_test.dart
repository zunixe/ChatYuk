import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/models/user_photo.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/providers/riverpod/chat_provider.dart';
import 'package:chatyuk/providers/riverpod/social_provider.dart';
import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/screens/user_info_screen.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/services/points_service.dart';

import 'test_helper.dart'
    show initSupabaseForTest, prewarmMediaForTest, resetFontForTest;

class MockAuthService extends Mock implements AuthService {}

class MockPointsService extends Mock implements PointsService {}

class TestAuth extends AuthNotifier {
  TestAuth(MockAuthService svc) : super(authService: svc);
  @override
  AuthData build() => const AuthData(loading: false);
  @override
  String? get uid => null;
}

class TestChat extends ChatNotifier {
  TestChat();
  @override
  ChatState build() => const ChatState();
  @override
  Stream<String> getUserStatus(String _, {String? initialStatus}) =>
      Stream<String>.value('offline');
}

class TestSocial extends SocialNotifier {
  TestSocial();
  @override
  SocialState build() => const SocialState();
  @override
  Future<Map<String, dynamic>> mySocialStatus(String _, {bool force = false}) async => {};
}

class TestPoints extends PointsNotifier {
  TestPoints(MockPointsService svc) : super(service: svc);
  @override
  PointsState build() => const PointsState(points: 50);
}

void main() {
  late MockAuthService authSvc;
  late MockPointsService pointsSvc;

  UserModel seed() {
    final now = DateTime.now();
    return UserModel(
      uid: '11111111-2222-3333-4444-555555555555',
      nickname: 'Sakti',
      gender: 'male',
      age: 0,
      country: '',
      city: '',
      ipAddress: '',
      status: '',
      avatar: '',
      isRegistered: true,
      loginAt: now,
      createdAt: now,
      lastSeen: now,
    );
  }

  Future<void> pumpUserInfo(
    WidgetTester t, {
    UserModel? initialProfile,
    Future<UserModel?> Function()? getProfileById,
    List<UserPhoto>? photos,
  }) async {
    authSvc = MockAuthService();
    when(() => authSvc.uid).thenReturn('99999999-2222-3333-4444-555555555555');
    when(() => authSvc.isAnonymous).thenReturn(false);
    when(() => authSvc.getProfileById('11111111-2222-3333-4444-555555555555')).thenAnswer(
      (_) => (getProfileById ?? () async => seed())(),
    );
    when(() => authSvc.getAvatarByPath(any())).thenAnswer((_) async => '');
    when(() => authSvc.getPhotosWithAccess(any()))
        .thenAnswer((_) async => photos ?? <UserPhoto>[]);

    pointsSvc = MockPointsService();
    when(() => pointsSvc.watchOwnPoints())
        .thenAnswer((_) => Stream<int>.empty());
    when(() => pointsSvc.meteredPricing()).thenAnswer((_) async => {});
    when(() => pointsSvc.featureFlags()).thenAnswer((_) async => {});
    when(() => pointsSvc.photoCosts()).thenAnswer((_) async => (5, 20));
    // subscribeOwnPoints() → refreshWallet() memanggil getWallet +
    // yukcoinV2Status; tanpa stub → error type-NoSuchMethod (noise log).
    when(() => pointsSvc.getWallet()).thenAnswer((_) async => {});
    when(() => pointsSvc.yukcoinV2Status()).thenAnswer((_) async => {});

    final container = ProviderContainer(
      overrides: [
        pointsProvider.overrideWith(() => TestPoints(pointsSvc)),
        authProvider.overrideWith(() => TestAuth(authSvc)),
        socialProvider.overrideWith(TestSocial.new),
        chatProvider.overrideWith(TestChat.new),
      ],
    );
    addTearDown(container.dispose);
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: UserInfoScreen(
            userId: '11111111-2222-3333-4444-555555555555',
            fallbackName: 'Sakti',
            initialProfile: initialProfile,
          ),
        ),
      ),
    );
    await t.pump();
  }

  setUpAll(() async {
    await initSupabaseForTest();
    // Prewarm cache media → MediaDiskCache.isReady = true sehingga
    // AvatarB64Service.get() TIDAK menjadwalkan Future.delayed retry
    // (penyebab "Pending timers" saat teardown). Pola sama post_card_test.
    await prewarmMediaForTest();
    // Font sistem (tanpa GoogleFonts runtime-fetch) supaya test hermetik —
    // sandbox CI/offline tidak bisa mengunduh Poppins.
    AppFonts.current = AppFonts.systemKey;
  });

  tearDownAll(() {
    resetFontForTest();
  });

  group('UserInfoScreen initialProfile — anti blink', () {
    testWidgets('tanpa seed + RPC tertahan → placeholder loading tampil',
        (t) async {
      final gate = Completer<UserModel?>();
      await pumpUserInfo(t, getProfileById: () => gate.future);

      // Fase loading: spinner ada (placeholder, bukan isi profil).
      expect(find.byType(CircularProgressIndicator), findsWidgets);

      gate.complete(seed());
      await t.pumpAndSettle();
      // Selesai load: spinner hilang, isi tampil.
      expect(find.text('Sakti'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('dengan seed + RPC tertahan → langsung isi, tanpa spinner',
        (t) async {
      final gate = Completer<UserModel?>();
      await pumpUserInfo(
        t,
        initialProfile: seed(),
        getProfileById: () => gate.future,
      );

      // Frame pertama SUDAH isi — tidak ada fase spinner/error.
      expect(find.text('Sakti'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Refresh selesai diam-diam → tetap isi, tetap tanpa spinner.
      gate.complete(seed());
      await t.pumpAndSettle();
      expect(find.text('Sakti'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('galeri: rebuild berulang tidak decode ulang / crash',
        (t) async {
      // PNG 1x1 valid — cukup untuk Image.memory tanpa fetch network.
      const tinyPng =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
      await pumpUserInfo(
        t,
        initialProfile: seed(),
        photos: [
          UserPhoto(
            id: 'p1',
            userId: '11111111-2222-3333-4444-555555555555',
            photo: tinyPng,
            createdAt: DateTime.now(),
          ),
          UserPhoto(
            id: 'p2',
            userId: '11111111-2222-3333-4444-555555555555',
            photo: tinyPng,
            createdAt: DateTime.now(),
          ),
        ],
      );
      await t.pumpAndSettle();

      // Galeri render (avatar + 2 foto).
      expect(find.byType(Image), findsWidgets);
      // Rebuild paksa (simulasi update status/sosial saat animasi pop):
      // tidak boleh throw dan gambar tetap ada (bytes dari cache).
      await t.pump();
      await t.pump();
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('dengan seed + RPC gagal → seed bertahan, tanpa error',
        (t) async {
      await pumpUserInfo(
        t,
        initialProfile: seed(),
        getProfileById: () => throw Exception('offline'),
      );
      // Majukan clock palsu melewati jeda retry 600ms supaya attempt kedua
      // ikut jalan (pumpAndSettle berhenti saat tak ada frame terjadwal dan
      // tidak memajukan timer ini → timer pending saat teardown).
      await t.pump(const Duration(milliseconds: 700));
      await t.pumpAndSettle();

      // Punya data seed → jangan tampilkan layar "Coba lagi".
      expect(find.text('Sakti'), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
