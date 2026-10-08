import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';

import 'package:chatyuk/config/fonts.dart';
import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/models/privacy_settings.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/providers/riverpod/privacy_provider.dart';
import 'package:chatyuk/screens/privacy_settings_screen.dart';
import 'package:chatyuk/services/privacy_service.dart';

import 'test_helper.dart';

/// Widget hermetic `PrivacySettingsScreen`: memastikan layar memakai string
/// bilingual (`s.`) dan meneruskannya ke `PrivacyNotifier` → `PrivacyService`
/// dengan argumen yang benar (bukan cuma "tidak crash").
class MockPrivacyService extends Mock implements PrivacyService {}

class _TestPrivacy extends PrivacyNotifier {
  _TestPrivacy(PrivacyService svc) : super(svc);
}

class _TestPoints extends PointsNotifier {
  _TestPoints();
  @override
  PointsState build() => const PointsState();
}

void main() {
  final s = S(isId: true);

  late MockPrivacyService service;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    AppFonts.setLocal(AppFonts.systemKey);
    await initSupabaseForTest();
  });

  tearDownAll(resetFontForTest);

  setUp(() {
    service = MockPrivacyService();
    when(() => service.fetch()).thenAnswer(
      (_) async => const PrivacySettings(),
    );
    // Default: update menerima argumen apa pun, hasil = settings saat ini.
    when(() => service.update(
          presence: any(named: 'presence'),
          lastSeen: any(named: 'lastSeen'),
          profilePhoto: any(named: 'profilePhoto'),
          about: any(named: 'about'),
          story: any(named: 'story'),
          readReceipts: any(named: 'readReceipts'),
        )).thenAnswer((_) async => const PrivacySettings());
    when(() => service.excludableUsers()).thenAnswer((_) async => const []);
    when(() => service.replaceExclusions(any(), any())).thenAnswer(
      (_) async => const PrivacySettings(),
    );
  });

  Widget wrap() => ProviderScope(
        overrides: [
          privacyProvider.overrideWith(() => _TestPrivacy(service)),
          pointsProvider.overrideWith(() => _TestPoints()),
        ],
        child: const MaterialApp(home: PrivacySettingsScreen()),
      );

  testWidgets('mount → load() sekali + tile memakai string bilingual',
      (tester) async {
    // Viewport tinggi: layar kini punya banyak tile (presence/last_seen/
    // profil/about/story/leaderboard/call + read receipts) → ListView lazy
    // tak membangun tile bawah di viewport 600px. Perbesar supaya semua tile
    // ada di tree (findsOneWidget valid untuk SEMUA, bukan cuma yang terlihat).
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    verify(() => service.fetch()).called(1);
    expect(find.text(s.privacyTitle), findsOneWidget);
    expect(find.text(s.privacyPresence), findsOneWidget);
    expect(find.text(s.privacyLastSeen), findsOneWidget);
    expect(find.text(s.privacyReadReceiptsTitle), findsOneWidget);
    expect(find.text(s.privacyHint), findsOneWidget);
  });

  testWidgets('tap tile presence → sheet 6 opsi visibility', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(s.privacyPresence));
    await tester.pumpAndSettle();

    expect(find.text(s.privacyEveryone), findsWidgets);
    expect(find.text(s.privacyEveryoneExcept), findsOneWidget);
    expect(find.text(s.privacyFriends), findsOneWidget);
    expect(find.text(s.privacyFriendsExcept), findsOneWidget);
    expect(find.text(s.privacyOnly), findsOneWidget);
    expect(find.text(s.privacyNobody), findsOneWidget);
  });

  testWidgets('pilih Hanya orang tertentu → update(presence: only) + picker',
      (tester) async {
    when(() => service.update(
          presence: PrivacyVisibility.only,
          lastSeen: null,
          profilePhoto: null,
          about: null,
          story: null,
          readReceipts: null,
        )).thenAnswer(
      (_) async => const PrivacySettings(presence: PrivacyVisibility.only),
    );
    when(() => service.excludableUsers()).thenAnswer(
      (_) async => [
        {'uid': 'u1', 'nickname': 'Budi', 'is_friend': true},
      ],
    );
    when(() => service.replaceExclusions('presence', {'u1'})).thenAnswer(
      (_) async => const PrivacySettings(
        presence: PrivacyVisibility.only,
        exclusions: {
          'presence': {'u1'},
        },
      ),
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(s.privacyPresence));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(s.privacyOnly));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.privacyOnly));
    await tester.pumpAndSettle();

    // Picker daftar putih tampil → pilih Budi lalu simpan.
    expect(find.text(s.privacyOnlyPickerTitle), findsOneWidget);
    await tester.tap(find.text('Budi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.btnSave));
    await tester.pumpAndSettle();

    // Daftar disimpan DULU, baru nilai 'only' (guard server butuh 1+ orang).
    verify(() => service.replaceExclusions('presence', {'u1'})).called(1);
    verify(() => service.update(
          presence: PrivacyVisibility.only,
          lastSeen: null,
          profilePhoto: null,
          about: null,
          story: null,
          readReceipts: null,
        )).called(1);
  });

  testWidgets('pilih nobody → update(presence) + subtitle berubah',
      (tester) async {
    when(() => service.update(
          presence: PrivacyVisibility.nobody,
          lastSeen: null,
          profilePhoto: null,
          about: null,
          story: null,
          readReceipts: null,
        )).thenAnswer(
      (_) async => const PrivacySettings(presence: PrivacyVisibility.nobody),
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(s.privacyPresence));
    await tester.pumpAndSettle();
    // Sheet kini 6 opsi — 'Tidak ada' bisa di bawah lipatan di viewport test.
    await tester.ensureVisible(find.text(s.privacyNobody));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.privacyNobody));
    await tester.pumpAndSettle();

    verify(() => service.update(
          presence: PrivacyVisibility.nobody,
          lastSeen: null,
          profilePhoto: null,
          about: null,
          story: null,
          leaderboard: null,
          readReceipts: null,
        )).called(1);
    expect(find.text(s.privacyNobody), findsOneWidget);
  });

  testWidgets('tile Top Aktif tampil + pilih Sembunyikan → update(leaderboard)',
      (tester) async {
    when(() => service.update(
          presence: null,
          lastSeen: null,
          profilePhoto: null,
          about: null,
          story: null,
          leaderboard: PrivacyVisibility.nobody,
          readReceipts: null,
        )).thenAnswer(
      (_) async => const PrivacySettings(leaderboard: PrivacyVisibility.nobody),
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // Tile "Top Aktif" tampil di layar Privasi.
    expect(find.text(s.privacyLeaderboard), findsOneWidget);

    await tester.tap(find.text(s.privacyLeaderboard));
    await tester.pumpAndSettle();
    // Sheet 6 opsi — 'Sembunyikan' bisa di bawah lipatan di viewport test.
    await tester.ensureVisible(find.text(s.privacyNobody));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.privacyNobody));
    await tester.pumpAndSettle();

    verify(() => service.update(
          presence: null,
          lastSeen: null,
          profilePhoto: null,
          about: null,
          story: null,
          leaderboard: PrivacyVisibility.nobody,
          readReceipts: null,
        )).called(1);
    expect(find.text(s.privacyNobody), findsOneWidget);
  });

  testWidgets('pilih Teman kecuali → picker + updateExclusions',
      (tester) async {
    when(() => service.excludableUsers()).thenAnswer(
      (_) async => [
        {'uid': 'u1', 'nickname': 'Budi', 'is_friend': true},
      ],
    );
    when(() => service.update(
          presence: PrivacyVisibility.friendsExcept,
          lastSeen: null,
          profilePhoto: null,
          about: null,
          story: null,
          readReceipts: null,
        )).thenAnswer(
      (_) async =>
          const PrivacySettings(presence: PrivacyVisibility.friendsExcept),
    );
    when(() => service.replaceExclusions('presence', {'u1'})).thenAnswer(
      (_) async => const PrivacySettings(
        presence: PrivacyVisibility.friendsExcept,
        exclusions: {
          'presence': {'u1'},
        },
      ),
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(s.privacyPresence));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.privacyFriendsExcept));
    await tester.pumpAndSettle();

    expect(find.text(s.privacyExceptTitle), findsOneWidget);
    expect(find.text('Budi'), findsOneWidget);

    await tester.tap(find.text('Budi'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.btnSave));
    await tester.pumpAndSettle();

    verify(() => service.replaceExclusions('presence', {'u1'})).called(1);
  });

  testWidgets('Semua kecuali → picker menampilkan teman & anon',
      (tester) async {
    when(() => service.excludableUsers()).thenAnswer(
      (_) async => [
        {'uid': 'u1', 'nickname': 'Budi', 'is_friend': true},
        {'uid': 'u2', 'nickname': 'Guest1', 'is_friend': false},
      ],
    );
    when(() => service.update(
          presence: PrivacyVisibility.everyoneExcept,
          lastSeen: null,
          profilePhoto: null,
          about: null,
          story: null,
          readReceipts: null,
        )).thenAnswer(
      (_) async =>
          const PrivacySettings(presence: PrivacyVisibility.everyoneExcept),
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(s.privacyPresence));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.privacyEveryoneExcept));
    await tester.pumpAndSettle();

    expect(find.text('Budi'), findsOneWidget);
    expect(find.text('Guest1'), findsOneWidget);
    expect(find.text(s.privacyBadgeFriend), findsOneWidget);
    expect(find.text(s.privacyBadgeAnon), findsOneWidget);
  });

  // Regresi 2026-09-29: dulu TextEditingController pencarian dibuat di layar
  // pemanggil & di-dispose tepat setelah `await showModalBottomSheet` →
  // "used after being disposed" saat animasi keluar masih jalan, memicu
  // assertion lanjutan `_dependents.isEmpty`. Sekarang controller dimiliki
  // sheet sendiri → mengetik lalu menutup harus aman.
  testWidgets('ketik di pencarian picker lalu tutup → tidak crash',
      (tester) async {
    when(() => service.excludableUsers()).thenAnswer(
      (_) async => [
        {'uid': 'u1', 'nickname': 'Budi', 'is_friend': true},
        {'uid': 'u2', 'nickname': 'Guest1', 'is_friend': false},
      ],
    );
    when(() => service.update(
          presence: PrivacyVisibility.everyoneExcept,
          lastSeen: null,
          profilePhoto: null,
          about: null,
          story: null,
          readReceipts: null,
        )).thenAnswer(
      (_) async =>
          const PrivacySettings(presence: PrivacyVisibility.everyoneExcept),
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(s.privacyPresence));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.privacyEveryoneExcept));
    await tester.pumpAndSettle();

    // Picker terbuka → ketik untuk memfilter.
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Bud');
    await tester.pumpAndSettle();
    expect(find.text('Budi'), findsOneWidget);
    expect(find.text('Guest1'), findsNothing);

    // Tutup lewat back (tanpa simpan) → animasi keluar jalan, controller
    // dibuang oleh dispose() milik sheet (bukan pemanggil).
    final nav = tester.state<NavigatorState>(find.byType(Navigator).last);
    nav.pop();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('kecuali tanpa kandidat → empty state', (tester) async {
    when(() => service.excludableUsers()).thenAnswer((_) async => const []);
    when(() => service.update(
          presence: PrivacyVisibility.friendsExcept,
          lastSeen: null,
          profilePhoto: null,
          about: null,
          story: null,
          readReceipts: null,
        )).thenAnswer(
      (_) async =>
          const PrivacySettings(presence: PrivacyVisibility.friendsExcept),
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(s.privacyPresence));
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.privacyFriendsExcept));
    await tester.pumpAndSettle();

    expect(find.text(s.privacyNoFriends), findsOneWidget);
    expect(find.text(s.privacyNoFriendsHint), findsOneWidget);
  });

  testWidgets('switch read receipts → update(readReceipts: false)',
      (tester) async {
    when(() => service.update(
          presence: null,
          lastSeen: null,
          profilePhoto: null,
          about: null,
          story: null,
          readReceipts: false,
        )).thenAnswer(
      (_) async => const PrivacySettings(readReceipts: false),
    );

    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    // Tap switch DI DALAM tile read-receipts (bukan Switch lain) — cari
    // switch yang se-descendant dgn judul read receipts (tile = ListTile).
    final tile = find.ancestor(
      of: find.text(s.privacyReadReceiptsTitle),
      matching: find.byType(ListTile),
    );
    final sw = find.descendant(of: tile, matching: find.byType(Switch));
    await tester.tap(sw.first);
    await tester.pumpAndSettle();

    verify(() => service.update(
          presence: null,
          lastSeen: null,
          profilePhoto: null,
          about: null,
          story: null,
          readReceipts: false,
        )).called(1);
  });
}
