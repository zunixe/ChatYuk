import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:chatyuk/config/strings.dart';
import 'package:chatyuk/models/user_model.dart';
import 'package:chatyuk/providers/riverpod/auth_provider.dart';
import 'package:chatyuk/providers/riverpod/chat_provider.dart';
import 'package:chatyuk/providers/riverpod/points_provider.dart';
import 'package:chatyuk/providers/riverpod/social_provider.dart';
import 'package:chatyuk/screens/account_screen.dart';
import 'package:chatyuk/screens/settings_screen.dart';
import 'package:chatyuk/services/auth_service.dart';
import 'package:chatyuk/services/chat_service.dart';
import 'package:chatyuk/services/social_service.dart';

import 'supabase_test_client.dart';

class MockAuthService extends Mock implements AuthService {}

class MockChatService extends Mock implements ChatService {}

class MockSocialService extends Mock implements SocialService {}

/// AuthNotifier uji — `isRealAdmin` bisa dipaksa (tanpa User Supabase).
class TestAuth extends AuthNotifier {
  final bool admin;
  TestAuth(MockAuthService svc, {this.admin = false})
      : super(authService: svc, autoInit: false);
  @override
  bool get isRealAdmin => admin;
}

/// ChatNotifier uji: hitung reset() tanpa menyentuh cache disk.
class TestChat extends ChatNotifier {
  TestChat(MockChatService svc) : super(service: svc);
  int resets = 0;
  @override
  void reset() {
    resets++;
  }
}

class TestSocial extends SocialNotifier {
  TestSocial(MockSocialService svc, SupabaseClient sb)
      : super(service: svc, sb: sb);
  @override
  SocialState build() => const SocialState();
}

class TestPoints extends PointsNotifier {
  @override
  PointsState build() => const PointsState();
}

UserModel profileForTest() => UserModel(
      uid: 'u-me',
      nickname: 'Me',
      gender: 'male',
      age: 20,
      country: 'Indonesia',
      city: 'Jakarta',
      ipAddress: '',
      status: 'online',
      avatar: '',
      isRegistered: true,
      loginAt: DateTime.now(),
      createdAt: DateTime.now(),
      lastSeen: DateTime.now(),
    );

/// Alur Pengaturan › Akun (rapihan profil): menu tampil, navigasi jalan,
/// Keluar terlihat, Hapus Akun sembunyi di ⋮.
void main() {
  late MockAuthService mockSvc;
  late ProviderContainer container;

  Future<void> pumpSettings(WidgetTester t, {bool admin = false}) async {
    mockSvc = MockAuthService();
    when(() => mockSvc.isAnonymous).thenReturn(false);
    when(() => mockSvc.isSignedIn).thenReturn(false);
    when(() => mockSvc.uid).thenReturn('u-me');
    when(() => mockSvc.dummySessionActive).thenReturn(false);
    when(() => mockSvc.emailConfirmed).thenReturn(true);
    when(() => mockSvc.userEmail).thenReturn('a@b.id');
    when(() => mockSvc.hasPassword).thenReturn(false);
    when(() => mockSvc.fetchHasPassword()).thenAnswer((_) async => false);
    container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => TestAuth(mockSvc, admin: admin)),
        pointsProvider.overrideWith(TestPoints.new),
      ],
    );
    addTearDown(container.dispose);
    container.read(authProvider.notifier).seedProfileForTest(profileForTest());
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets('menu Pengaturan tampil + Akun bisa dibuka', (t) async {
    await pumpSettings(t);

    expect(find.text('Pengaturan'), findsWidgets);
    expect(find.text('Akun'), findsOneWidget);

    await t.tap(find.text('Akun'));
    await t.pumpAndSettle();

    expect(find.byType(AccountScreen), findsOneWidget);
  });

  testWidgets('layar Akun: Keluar terlihat, Hapus Akun di ⋮', (t) async {
    await pumpSettings(t);
    await t.tap(find.text('Akun'));
    await t.pumpAndSettle();

    expect(find.text('Keluar'), findsOneWidget);
    // Hapus Akun TIDAK tampil sebagai baris (tersembunyi di ⋮).
    expect(find.text('Hapus Akun'), findsNothing);

    await t.tap(find.byIcon(Icons.more_vert));
    await t.pumpAndSettle();

    expect(find.text('Hapus Akun'), findsOneWidget);
  });

  group('layar Akun: password/hapus/keluar', () {
    late MockAuthService authSvc;
    late MockChatService chatSvc;
    late MockSocialService socialSvc;
    late TestChat testChat;

    Future<void> pumpAccount(
      WidgetTester t, {
      bool adminEmail = false,
      bool anon = false,
    }) async {
      // Wajib: provider.signOut baca SharedPreferences (cache profil).
      SharedPreferences.setMockInitialValues({});
      authSvc = MockAuthService();
      when(() => authSvc.isAnonymous).thenReturn(anon);
      when(() => authSvc.isSignedIn).thenReturn(false);
      when(() => authSvc.dummySessionActive).thenReturn(false);
      when(() => authSvc.emailConfirmed).thenReturn(true);
      when(() => authSvc.userEmail)
          .thenReturn(adminEmail ? 'zunixe@gmail.com' : 'a@b.id');
      when(() => authSvc.hasPassword).thenReturn(false);
      when(() => authSvc.fetchHasPassword()).thenAnswer((_) async => false);
      when(() => authSvc.deleteMyAccount()).thenAnswer((_) async {});
      when(() => authSvc.goOffline()).thenAnswer((_) async {});
      when(() => authSvc.signOut()).thenAnswer((_) async {});
      when(() => authSvc.setPassword(any())).thenAnswer((_) async {});
      chatSvc = MockChatService();
      testChat = TestChat(chatSvc);
      socialSvc = MockSocialService();
      when(() => socialSvc.clearAnonSocial()).thenAnswer((_) async {});
      container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(() => TestAuth(authSvc, admin: adminEmail)),
          chatProvider.overrideWith(() => testChat),
          socialProvider.overrideWith(
            () => TestSocial(socialSvc, fakeSupabaseClientNoTicker()),
          ),
          pointsProvider.overrideWith(TestPoints.new),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(authProvider.notifier)
          .seedProfileForTest(profileForTest());
      await t.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: AccountScreen()),
        ),
      );
      await t.pumpAndSettle();
    }

    Future<void> openDeleteMenu(WidgetTester t) async {
      await t.tap(find.byIcon(Icons.more_vert));
      await t.pumpAndSettle();
      await t.tap(find.text('Hapus Akun'));
      await t.pumpAndSettle();
    }

    testWidgets('password pendek → error, service tak dipanggil', (t) async {
      await pumpAccount(t);

      await t.tap(find.text('Set Password'));
      await t.pumpAndSettle();
      // Dialog set (tanpa field password saat ini).
      expect(find.text('Password Saat Ini'), findsNothing);

      await t.enterText(
        find.widgetWithText(TextField, 'Password'),
        'pendek',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Konfirmasi Password'),
        'pendek',
      );
      await t.tap(find.text('Simpan'));
      await t.pump();

      expect(find.text('Password minimal 8 karakter'), findsOneWidget);
    });

    testWidgets('password beda → error mismatch', (t) async {
      await pumpAccount(t);

      await t.tap(find.text('Set Password'));
      await t.pumpAndSettle();
      await t.enterText(
        find.widgetWithText(TextField, 'Password'),
        'rahasia123',
      );
      await t.enterText(
        find.widgetWithText(TextField, 'Konfirmasi Password'),
        'lain1234',
      );
      await t.tap(find.text('Simpan'));
      await t.pump();

      expect(find.text('Passwords do not match'), findsNothing);
      expect(find.text('Password tidak cocok'), findsOneWidget);
    });

    testWidgets('hapus akun admin → ditolak, service diam', (t) async {
      await pumpAccount(t, adminEmail: true);
      await openDeleteMenu(t);
      await t.pumpAndSettle();

      verifyNever(() => authSvc.deleteMyAccount());
      verifyNever(() => authSvc.signOut());
    });

    testWidgets('hapus akun batal step1 → service diam', (t) async {
      await pumpAccount(t);
      await openDeleteMenu(t);

      await t.tap(find.text('Batal'));
      await t.pumpAndSettle();

      verifyNever(() => authSvc.deleteMyAccount());
      expect(find.text('HAPUS / DELETE'), findsNothing);
    });

    testWidgets('hapus akun HAPUS → delete + signOut + reset', (t) async {
      await pumpAccount(t);
      await openDeleteMenu(t);

      // Step1: lanjutkan (tombol merah di dialog).
      await t.tap(find.widgetWithText(FilledButton, 'Hapus Akun'));
      await t.pumpAndSettle();

      // Step2: ketik HAPUS → tombol aktif → eksekusi.
      await t.enterText(find.byType(TextField), 'HAPUS');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Hapus Akun'));
      await t.pumpAndSettle();

      verify(() => authSvc.deleteMyAccount()).called(1);
      verify(() => authSvc.signOut()).called(1);
      expect(testChat.resets, 1);
      verifyNever(() => socialSvc.clearAnonSocial());
    });

    testWidgets('hapus akun anon → clearAnonSocial dulu', (t) async {
      await pumpAccount(t, anon: true);
      // Tile anon: langsung ke ⋮ (email tile tidak ada untuk anon).
      await t.tap(find.byIcon(Icons.more_vert));
      await t.pumpAndSettle();
      await t.tap(find.text('Hapus Akun'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Hapus Akun'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'DELETE');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Hapus Akun'));
      await t.pumpAndSettle();

      verify(() => socialSvc.clearAnonSocial()).called(1);
      verify(() => authSvc.deleteMyAccount()).called(1);
    });

    testWidgets('keluar batal → signOut diam', (t) async {
      await pumpAccount(t);

      await t.tap(find.text('Keluar'));
      await t.pumpAndSettle();
      await t.tap(find.text('Batal'));
      await t.pumpAndSettle();

      verifyNever(() => authSvc.signOut());
    });

    testWidgets('keluar konfirm → signOut + reset', (t) async {
      await pumpAccount(t);

      await t.tap(find.text('Keluar'));
      await t.pumpAndSettle();
      await t.tap(find.text('Keluar').last);
      await t.pumpAndSettle();

      verify(() => authSvc.signOut()).called(1);
      expect(testChat.resets, 1);
    });

    testWidgets('keluar anon clear gagal → tetap keluar', (t) async {
      await pumpAccount(t, anon: true);
      when(() => socialSvc.clearAnonSocial())
          .thenThrow(Exception('network down'));

      await t.tap(find.text('Keluar'));
      await t.pumpAndSettle();
      await t.tap(find.text('Keluar').last);
      await t.pumpAndSettle();

      verify(() => authSvc.signOut()).called(1);
      expect(testChat.resets, 1);
    });

    testWidgets(
        'hapus akun anon: kartu kuning hilang sejak konfirmasi (anti-kedip)',
        (t) async {
      await pumpAccount(t, anon: true);
      final warn = S(isId: true).msgAnonymousWarning;
      // Sebelum proses: kartu peringatan anon tampil (kondisi normal).
      expect(find.text(warn), findsOneWidget);

      // Tahan RPC supaya alur "sedang berjalan" (provider signingOut MASIH
      // false di window ini — celah yang dulu membuat kartu berkedip).
      final deleteGate = Completer<void>();
      final signOutGate = Completer<void>();
      when(() => authSvc.deleteMyAccount())
          .thenAnswer((_) => deleteGate.future);
      when(() => authSvc.signOut()).thenAnswer((_) => signOutGate.future);

      await openDeleteMenu(t);
      await t.tap(find.widgetWithText(FilledButton, 'Hapus Akun'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'HAPUS');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Hapus Akun'));
      await t.pump();

      // Selama RPC berjalan: kartu kuning TIDAK boleh render frame mana pun.
      expect(find.text(warn), findsNothing);

      deleteGate.complete();
      signOutGate.complete();
      await t.pumpAndSettle();

      verify(() => authSvc.deleteMyAccount()).called(1);
      expect(find.text(warn), findsNothing);
    });

    testWidgets('keluar anon: kartu kuning hilang sejak konfirmasi',
        (t) async {
      await pumpAccount(t, anon: true);
      final warn = S(isId: true).msgAnonymousWarning;
      expect(find.text(warn), findsOneWidget);

      // Tahan signOut supaya alur "sedang berjalan".
      final signOutGate = Completer<void>();
      when(() => authSvc.signOut()).thenAnswer((_) => signOutGate.future);

      await t.tap(find.text('Keluar'));
      await t.pumpAndSettle();
      await t.tap(find.text('Keluar').last);
      await t.pump();

      // Sejak konfirmasi (termasuk jeda 200ms + clearAnonSocial): kartu
      // kuning TIDAK boleh render frame mana pun.
      expect(find.text(warn), findsNothing);

      await t.pump(const Duration(milliseconds: 300));
      expect(find.text(warn), findsNothing);

      signOutGate.complete();
      await t.pumpAndSettle();

      verify(() => authSvc.signOut()).called(1);
    });
  });
}
