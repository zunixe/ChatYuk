import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/models/privacy_settings.dart';
import 'package:chatyuk/providers/privacy_provider.dart';
import 'package:chatyuk/screens/online_users_screen.dart';
import 'package:chatyuk/services/privacy_service.dart';

import 'test_helper.dart';

class MockPrivacyService extends Mock implements PrivacyService {}

/// Mengunci fitur "Status kamu" (halaman Pengguna Online):
/// - Pemetaan visibilitas → chip + subbaris (khususnya kasus "kecuali N orang"
///   supaya "Semua orang" tidak menyesatkan — status online tapi sebagian
///   orang melihat Offline).
/// - Sheet menampilkan status + visibilitas + foto.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final s = S(isId: true);

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    AppFonts.setLocal(AppFonts.systemKey);
    await initSupabaseForTest();
  });

  tearDownAll(resetFontForTest);

  group('myStatusVisibilityChip', () {
    test('everyone → chip saja, tanpa subbaris', () {
      final (chip, sub) =
          myStatusVisibilityChip(s, PrivacyVisibility.everyone, 0);
      expect(chip, s.myStatusVisibleEveryone);
      expect(sub, isNull);
    });

    test('friends → chip hanya teman', () {
      final (chip, sub) =
          myStatusVisibilityChip(s, PrivacyVisibility.friends, 0);
      expect(chip, s.myStatusVisibleFriends);
      expect(sub, isNull);
    });

    test('nobody → tampak Offline', () {
      final (chip, sub) =
          myStatusVisibilityChip(s, PrivacyVisibility.nobody, 0);
      expect(chip, s.myStatusVisibleNobody);
      expect(sub, s.myStatusTheySeeOffline);
    });

    test('everyone_except(N) → subbaris menyebut "kecuali N + lihat Offline"',
        () {
      final (chip, sub) =
          myStatusVisibilityChip(s, PrivacyVisibility.everyoneExcept, 3);
      expect(chip, s.myStatusVisibleEveryone);
      expect(sub, s.myStatusExceptNAndOffline(3));
      expect(sub, isNotNull);
    });

    test('everyone_except(0) → tanpa subbaris (tak ada pengecualian)', () {
      final (_, sub) =
          myStatusVisibilityChip(s, PrivacyVisibility.everyoneExcept, 0);
      expect(sub, isNull);
    });

    test('friends_except(N) → subbaris "kecuali N"', () {
      final (chip, sub) =
          myStatusVisibilityChip(s, PrivacyVisibility.friendsExcept, 2);
      expect(chip, s.myStatusVisibleFriends);
      expect(sub, s.myStatusExceptN(2));
    });

    test('only(N) → chip "Hanya N orang"', () {
      final (chip, sub) =
          myStatusVisibilityChip(s, PrivacyVisibility.only, 5);
      expect(chip, s.myStatusVisibleOnly(5));
      expect(sub, isNull);
    });
  });

  group('MyStatusSheet (widget)', () {
    late MockPrivacyService svc;
    late PrivacyProvider privacy;

    void stubSettings(PrivacySettings st) {
      when(() => svc.fetch()).thenAnswer((_) async => st);
    }

    setUp(() {
      svc = MockPrivacyService();
      privacy = PrivacyProvider(service: svc);
    });

    tearDown(() => privacy.dispose());

    Future<void> pump(
      WidgetTester tester, {
      required PrivacySettings st,
      String status = 'online',
      bool invisible = false,
    }) async {
      stubSettings(st);
      await privacy.load();
      await tester.pumpWidget(
        ChangeNotifierProvider<PrivacyProvider>.value(
          value: privacy,
          child: MaterialApp(
            home: Scaffold(
              body: MyStatusSheet(
                s: s,
                nickname: 'Budi',
                avatar: '',
                status: status,
                invisible: invisible,
                privacy: privacy,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('online + everyone → status & visibilitas tampil', (t) async {
      await pump(t, st: const PrivacySettings());
      expect(find.text(s.myStatusTitle), findsOneWidget);
      expect(find.text(s.statusOnline), findsOneWidget);
      expect(find.text(s.myStatusVisibleEveryone), findsWidgets);
      // Ghost tidak aktif → tak ada label mode hantu.
      expect(find.text(s.myStatusGhostActive), findsNothing);
    });

    testWidgets('ghost aktif → label mode hantu + tetap tampil Online',
        (t) async {
      await pump(t, st: const PrivacySettings(), invisible: true);
      // Status teknis tetap Online (bukan ditulis "Invisible").
      expect(find.text(s.statusOnline), findsOneWidget);
      expect(find.text(s.myStatusGhostActive), findsOneWidget);
    });

    testWidgets('everyone_except(2) → subbaris pengecualian tampil',
        (t) async {
      await pump(
        t,
        st: const PrivacySettings(
          presence: PrivacyVisibility.everyoneExcept,
          exclusions: {
            'presence': {'u1', 'u2'},
          },
        ),
      );
      expect(find.text(s.myStatusExceptNAndOffline(2)), findsOneWidget);
    });

    testWidgets('foto profil privat → chip "Hanya teman" tampil', (t) async {
      await pump(
        t,
        st: const PrivacySettings(
          profilePhoto: PrivacyVisibility.friends,
        ),
      );
      expect(find.text(s.myStatusPhotoLabel), findsOneWidget);
      expect(find.text(s.myStatusVisibleFriends), findsWidgets);
    });
  });
}
