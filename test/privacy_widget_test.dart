import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/models/privacy_settings.dart';
import 'package:chatyuk/providers/locale_provider.dart';
import 'package:chatyuk/providers/privacy_provider.dart';
import 'package:chatyuk/screens/privacy_settings_screen.dart';
import 'package:chatyuk/services/privacy_service.dart';

/// Widget hermetic `PrivacySettingsScreen`: memastikan layar memakai string
/// bilingual (`s.`) dan meneruskannya ke `PrivacyProvider` → `PrivacyService`
/// dengan argumen yang benar (bukan cuma "tidak crash").
class MockPrivacyService extends Mock implements PrivacyService {}

void main() {
  final s = S(isId: true);

  late MockPrivacyService service;
  late PrivacyProvider provider;

  setUp(() {
    service = MockPrivacyService();
    provider = PrivacyProvider(service: service);
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

  tearDown(() => provider.dispose());

  Widget wrap() => MultiProvider(
        providers: [
          ChangeNotifierProvider<LocaleProvider>(
            create: (_) => LocaleProvider(),
          ),
          ChangeNotifierProvider<PrivacyProvider>.value(value: provider),
        ],
        child: const MaterialApp(home: PrivacySettingsScreen()),
      );

  testWidgets('mount → load() sekali + tile memakai string bilingual',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    verify(() => service.fetch()).called(1);
    expect(find.text(s.privacyTitle), findsOneWidget);
    expect(find.text(s.privacyPresence), findsOneWidget);
    expect(find.text(s.privacyLastSeen), findsOneWidget);
    expect(find.text(s.privacyReadReceiptsTitle), findsOneWidget);
    expect(find.text(s.privacyHint), findsOneWidget);
  });

  testWidgets('tap tile presence → sheet 5 opsi visibility', (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text(s.privacyPresence));
    await tester.pumpAndSettle();

    expect(find.text(s.privacyEveryone), findsWidgets);
    expect(find.text(s.privacyEveryoneExcept), findsOneWidget);
    expect(find.text(s.privacyFriends), findsOneWidget);
    expect(find.text(s.privacyFriendsExcept), findsOneWidget);
    expect(find.text(s.privacyNobody), findsOneWidget);
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
    await tester.tap(find.text(s.privacyNobody));
    await tester.pumpAndSettle();

    verify(() => service.update(
          presence: PrivacyVisibility.nobody,
          lastSeen: null,
          profilePhoto: null,
          about: null,
          story: null,
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

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
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
